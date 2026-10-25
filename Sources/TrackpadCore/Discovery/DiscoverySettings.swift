import CoreGraphics
import Foundation

/// Settings for the Gesture Discovery HUD, the card that lists an app's gestures.
public struct DiscoverySettings: Sendable, Codable, Equatable {
    public enum Scope: String, Sendable, Codable, CaseIterable {
        /// Only apps that have their own per-app gestures.
        case appsWithOwnGestures
        /// Every app that has any gesture, including global ones.
        case allApps

        public var displayName: String {
            switch self {
            case .appsWithOwnGestures: "Apps with their own gestures"
            case .allApps: "Every app"
            }
        }
    }

    public var isEnabled = true
    public var scope = Scope.appsWithOwnGestures
    /// Seconds the card stays when not hovered.
    public var displayDuration: TimeInterval = 6
    /// Bundle IDs the user chose "Don't show again" for.
    public var mutedApps: [String] = []
    /// Shows the card for the frontmost app on demand. Default ⌃⌥⌘G.
    public var hotkey: KeyCombo? = KeyCombo(
        keyCode: 5, modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
    )

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiscoverySettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? d.scope
        displayDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .displayDuration) ?? d.displayDuration
        mutedApps = try c.decodeIfPresent([String].self, forKey: .mutedApps) ?? d.mutedApps
        hotkey = c.contains(.hotkey) ? try c.decodeIfPresent(KeyCombo.self, forKey: .hotkey) : d.hotkey
    }
}

/// Decides when the discovery card appears automatically.
///
/// The card shows the first time a freshly launched app comes to the front
/// (tracked by process ID, so relaunching an app shows it again).
public struct DiscoveryPolicy: Sendable {
    private var seenProcesses: Set<Int32> = []

    public init() {}

    /// Gestures to list for `bundleID`, or nil if the card should not show.
    /// Marks the process as seen either way.
    public mutating func gesturesToAnnounce(
        bundleID: String?, processID: Int32, mode: Mode, settings: DiscoverySettings
    ) -> [GestureBinding]? {
        guard seenProcesses.insert(processID).inserted else { return nil }
        guard settings.isEnabled, let bundleID, !settings.mutedApps.contains(bundleID) else { return nil }
        let hasOwn = mode.appProfiles.contains { $0.bundleID == bundleID && $0.bindings.contains(where: \.isEnabled) }
        guard settings.scope == .allApps || hasOwn else { return nil }
        let bindings = mode.effectiveBindings(for: bundleID)
        return bindings.isEmpty ? nil : bindings
    }

    /// Forgets processes that have quit, so the set does not grow forever.
    public mutating func prune(keeping running: Set<Int32>) {
        seenProcesses.formIntersection(running)
    }
}
