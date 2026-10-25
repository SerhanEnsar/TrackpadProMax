import AppKit
import Foundation

/// The track currently playing, from whichever source could tell us.
public struct NowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool
    /// Bundle ID of the player app, used for its icon.
    public var appBundleID: String?
    public var artwork: Data?

    public var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
}

/// Reads and seeks the playing track.
///
/// 1. MediaRemote (private) covers any player, but recent macOS versions may
///    hide its data from third-party apps.
/// 2. Fallback: AppleScript to Music or Spotify, only if already running
///    (never launches them). Needs the Automation permission once per app.
public final class NowPlayingCenter: @unchecked Sendable {
    public static let shared = NowPlayingCenter()

    private let queue = DispatchQueue(label: "TrackpadProMax.nowplaying", qos: .userInitiated)
    private let remote = MediaRemote()

    private init() {}

    /// Calls `completion` on the main actor with the current track, or nil.
    public func fetch(_ completion: @escaping @MainActor @Sendable (NowPlaying?) -> Void) {
        remote.nowPlaying { [queue] info in
            if let info {
                Task { @MainActor in completion(info) }
                return
            }
            queue.async {
                let info = ScriptedPlayers.nowPlaying()
                Task { @MainActor in completion(info) }
            }
        }
    }

    /// Jumps to `seconds` in the current track.
    public func seek(to seconds: TimeInterval, appBundleID: String?) {
        queue.async { [remote] in
            if let appBundleID, ScriptedPlayers.isScriptable(appBundleID) {
                ScriptedPlayers.seek(appBundleID, to: seconds)
            } else {
                remote.seek(to: seconds)
            }
        }
    }
}

// MARK: - MediaRemote

private final class MediaRemote: @unchecked Sendable {
    typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    typealias SetElapsed = @convention(c) (Double) -> Void

    private let getInfo: GetInfo?
    private let setElapsed: SetElapsed?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        getInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo").map { unsafeBitCast($0, to: GetInfo.self) }
        setElapsed = dlsym(handle, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsed.self) }
    }

    func nowPlaying(_ completion: @escaping @Sendable (NowPlaying?) -> Void) {
        guard let getInfo else { return completion(nil) }
        getInfo(DispatchQueue.global(qos: .userInitiated)) { dict in
            guard let dict = dict as? [String: Any], let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String else {
                return completion(nil)
            }
            let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            var elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
            // Elapsed time is a snapshot; advance it to now while playing.
            if rate > 0, let stamp = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                elapsed += Date().timeIntervalSince(stamp) * rate
            }
            completion(NowPlaying(
                title: title,
                artist: dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                elapsed: elapsed,
                duration: dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
                isPlaying: rate > 0,
                appBundleID: nil,
                artwork: dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            ))
        }
    }

    func seek(to seconds: TimeInterval) {
        setElapsed?(seconds)
    }
}

// MARK: - AppleScript players

private enum ScriptedPlayers {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"

    static func isScriptable(_ bundleID: String) -> Bool { bundleID == music || bundleID == spotify }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func appName(_ bundleID: String) -> String { bundleID == music ? "Music" : "Spotify" }

    static func nowPlaying() -> NowPlaying? {
        var paused: NowPlaying?
        for bundleID in [music, spotify] where isRunning(bundleID) {
            guard let track = query(bundleID) else { continue }
            if track.isPlaying { return track }
            paused = paused ?? track
        }
        return paused
    }

    private static func query(_ bundleID: String) -> NowPlaying? {
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpr = bundleID == spotify ? "(duration of current track) / 1000" : "duration of current track"
        let script = """
        tell application "\(appName(bundleID))"
            if player state is stopped then return ""
            set sep to (ASCII character 31)
            return (name of current track) & sep & (artist of current track) & sep & ¬
                (player position as text) & sep & (\(durationExpr) as text) & sep & (player state as text)
        end tell
        """
        guard let output = run(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "\u{1F}")
        guard parts.count == 5 else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return NowPlaying(
            title: parts[0], artist: parts[1], elapsed: number(parts[2]), duration: number(parts[3]),
            isPlaying: parts[4].contains("playing"), appBundleID: bundleID, artwork: nil
        )
    }

    static func seek(_ bundleID: String, to seconds: TimeInterval) {
        guard isRunning(bundleID) else { return }
        _ = run("tell application \"\(appName(bundleID))\" to set player position to \(String(format: "%.2f", seconds))")
    }

    /// Runs through `osascript` so a slow or hung player never blocks the app.
    private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
