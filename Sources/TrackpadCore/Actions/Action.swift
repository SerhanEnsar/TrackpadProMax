import Foundation

/// A key plus modifiers, stored as virtual key code and `CGEventFlags` raw value.
public struct KeyCombo: Hashable, Sendable, Codable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum MouseButton: String, Sendable, Codable, CaseIterable {
    case left, right, middle
}

public enum SystemAction: String, Sendable, Codable, CaseIterable {
    case missionControl, appWindows, showDesktop
    case screenshot, lockScreen
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown

    public var displayName: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appWindows: "App windows"
        case .showDesktop: "Show desktop"
        case .screenshot: "Screenshot"
        case .lockScreen: "Lock screen"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness up"
        case .brightnessDown: "Brightness down"
        }
    }
}

/// What happens when a trigger fires.
public enum Action: Hashable, Sendable, Codable {
    case keyboardShortcut(KeyCombo)
    case mouseClick(MouseButton)
    case system(SystemAction)
    case launchApp(path: String)
    case openURL(String)
    /// Runs a shortcut from the Shortcuts app by name.
    case runShortcut(name: String)
    case appleScript(source: String)
    /// Cycles to the next trackpad mode.
    case nextMode

    public var displayName: String {
        switch self {
        case let .keyboardShortcut(combo): "Shortcut \(KeyNames.describe(combo))"
        case let .mouseClick(button): "\(button.rawValue.capitalized) click"
        case let .system(action): action.displayName
        case let .launchApp(path): "Open \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)"
        case let .openURL(url): "Open \(url)"
        case let .runShortcut(name): "Run shortcut “\(name)”"
        case .appleScript: "Run AppleScript"
        case .nextMode: "Next trackpad mode"
        }
    }
}
