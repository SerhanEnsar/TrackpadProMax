import CoreGraphics
import Foundation

/// One trigger → action rule.
public struct GestureBinding: Identifiable, Hashable, Sendable, Codable {
    public var id = UUID()
    public var trigger: Trigger
    public var action: Action
    public var isEnabled = true

    public init(trigger: Trigger, action: Action, isEnabled: Bool = true) {
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// Bindings that only apply while a given app is frontmost.
public struct AppProfile: Identifiable, Hashable, Sendable, Codable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String
    public var bindings: [GestureBinding]

    public init(bundleID: String, appName: String, bindings: [GestureBinding] = []) {
        self.bundleID = bundleID
        self.appName = appName
        self.bindings = bindings
    }
}

/// A switchable set of bindings, e.g. "Normal" or "Media".
public struct Mode: Identifiable, Hashable, Sendable, Codable {
    public var id = UUID()
    public var name: String
    /// SF Symbol shown in the menu bar while the mode is active.
    public var symbol: String
    public var bindings: [GestureBinding]
    public var appProfiles: [AppProfile]

    public init(name: String, symbol: String, bindings: [GestureBinding] = [], appProfiles: [AppProfile] = []) {
        self.name = name
        self.symbol = symbol
        self.bindings = bindings
        self.appProfiles = appProfiles
    }

    /// Bindings that apply in `bundleID`, app-specific first.
    public func effectiveBindings(for bundleID: String?) -> [GestureBinding] {
        let app = appProfiles.first { $0.bundleID == bundleID }?.bindings ?? []
        return (app + bindings).filter(\.isEnabled)
    }

    /// The best binding for a recognized event: app-specific beats global,
    /// an exact zone beats `.anywhere`.
    public func binding(for event: Trigger, bundleID: String?) -> GestureBinding? {
        let candidates = effectiveBindings(for: bundleID).filter { $0.trigger.matches(event) }
        return candidates.first { $0.trigger.zone != .anywhere } ?? candidates.first
    }
}

/// Everything the user can configure. Persisted as JSON.
public struct Configuration: Sendable, Codable, Equatable {
    /// Bumped when stored values need migrating. See `migrate()`.
    public static let currentSchemaVersion = 1

    public var schemaVersion = Configuration.currentSchemaVersion
    public var isEnabled = true
    public var modes: [Mode]
    public var activeModeID: UUID
    public var gestures = GestureSettings()
    /// Short haptic confirmation whenever a binding fires.
    public var hapticOnTrigger = true
    public var triggerHaptic: HapticPattern = .weak
    /// Global hotkey that cycles modes. Default ⌃⌥⌘T.
    public var modeHotkey: KeyCombo? = KeyCombo(
        keyCode: 17, modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
    )

    public init(modes: [Mode], activeModeID: UUID? = nil) {
        precondition(!modes.isEmpty, "Configuration needs at least one mode")
        self.modes = modes
        self.activeModeID = activeModeID ?? modes[0].id
    }

    /// Missing keys fall back to defaults so older settings files keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let modes = try c.decode([Mode].self, forKey: .modes)
        guard !modes.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .modes, in: c, debugDescription: "No modes")
        }
        self.init(modes: modes, activeModeID: try c.decodeIfPresent(UUID.self, forKey: .activeModeID))
        let d = Configuration(modes: modes)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        gestures = try c.decodeIfPresent(GestureSettings.self, forKey: .gestures) ?? d.gestures
        hapticOnTrigger = try c.decodeIfPresent(Bool.self, forKey: .hapticOnTrigger) ?? d.hapticOnTrigger
        triggerHaptic = try c.decodeIfPresent(HapticPattern.self, forKey: .triggerHaptic) ?? d.triggerHaptic
        modeHotkey = c.contains(.modeHotkey) ? try c.decodeIfPresent(KeyCombo.self, forKey: .modeHotkey) : d.modeHotkey
        if !modes.contains(where: { $0.id == activeModeID }) { activeModeID = modes[0].id }
        migrate()
    }

    /// Upgrades values written by older versions.
    mutating func migrate() {
        if schemaVersion < 1 {
            // Pre-0.1 thresholds were guesses that made firm taps count as presses.
            var old = GestureSettings()
            (old.lightThreshold, old.mediumThreshold, old.hardThreshold, old.maxTapMovement) = (60, 220, 420, 0.03)
            if gestures == old { gestures = GestureSettings() }
        }
        schemaVersion = Self.currentSchemaVersion
    }

    public var activeMode: Mode {
        get { modes.first { $0.id == activeModeID } ?? modes[0] }
        set {
            if let index = modes.firstIndex(where: { $0.id == newValue.id }) { modes[index] = newValue }
        }
    }

    public mutating func selectNextMode() {
        let index = modes.firstIndex { $0.id == activeModeID } ?? 0
        activeModeID = modes[(index + 1) % modes.count].id
    }

    public static var defaults: Configuration {
        let normal = Mode(name: "Normal", symbol: "hand.point.up.left", bindings: [
            GestureBinding(trigger: .tap(fingers: 3, count: 1, zone: .anywhere), action: .mouseClick(.middle)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .topRight), action: .system(.missionControl)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .topLeft), action: .system(.showDesktop)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .bottomRight), action: .system(.screenshot)),
            GestureBinding(trigger: .tap(fingers: 4, count: 2, zone: .anywhere), action: .nextMode),
        ])
        let media = Mode(name: "Media", symbol: "play.circle", bindings: [
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .center), action: .system(.playPause)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .leftEdge), action: .system(.previousTrack)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .rightEdge), action: .system(.nextTrack)),
            GestureBinding(trigger: .press(tier: .medium, fingers: 1, zone: .topEdge), action: .system(.volumeUp)),
            GestureBinding(trigger: .press(tier: .medium, fingers: 1, zone: .bottomEdge), action: .system(.volumeDown)),
            GestureBinding(trigger: .tap(fingers: 3, count: 1, zone: .anywhere), action: .system(.mute)),
            GestureBinding(trigger: .tap(fingers: 4, count: 2, zone: .anywhere), action: .nextMode),
        ])
        return Configuration(modes: [normal, media])
    }
}
