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
    /// Non-nil for a control surface mode: the whole trackpad becomes edge
    /// bars (volume, brightness, …) and gesture bindings are not used.
    public var surface: ControlSurfaceLayout?
    /// Non-nil for a tool mode (window tiling, app launcher, …).
    public var tool: ModeTool?

    public init(
        name: String, symbol: String, bindings: [GestureBinding] = [], appProfiles: [AppProfile] = [],
        surface: ControlSurfaceLayout? = nil, tool: ModeTool? = nil
    ) {
        self.name = name
        self.symbol = symbol
        self.bindings = bindings
        self.appProfiles = appProfiles
        self.surface = surface
        self.tool = tool
    }

    public var isControlSurface: Bool { surface != nil }

    /// Surfaces and tools take over the whole trackpad with an overlay;
    /// everything else is a gesture mode.
    public var isOverlay: Bool { surface != nil || tool != nil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "star"
        bindings = try c.decodeIfPresent([GestureBinding].self, forKey: .bindings) ?? []
        appProfiles = try c.decodeIfPresent([AppProfile].self, forKey: .appProfiles) ?? []
        surface = try c.decodeIfPresent(ControlSurfaceLayout.self, forKey: .surface)
        tool = try? c.decodeIfPresent(ModeTool.self, forKey: .tool)
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
    public static let currentSchemaVersion = 5

    public var schemaVersion = Configuration.currentSchemaVersion
    public var isEnabled = true
    public var modes: [Mode]
    public var activeModeID: UUID
    public var gestures = GestureSettings()
    /// Short haptic confirmation whenever a binding fires.
    public var hapticOnTrigger = true
    public var triggerHaptic: HapticPattern = .weak
    public var discovery = DiscoverySettings()
    /// Bundle IDs on the launcher wheel; empty means "use the Dock's apps".
    public var launcherApps: [String] = []
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
        discovery = try c.decodeIfPresent(DiscoverySettings.self, forKey: .discovery) ?? d.discovery
        launcherApps = try c.decodeIfPresent([String].self, forKey: .launcherApps) ?? d.launcherApps
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
        if schemaVersion < 2 {
            // 0.2: the four-finger double tap opens the mode wheel instead of
            // cycling modes, and a Control surface mode joins the defaults.
            for index in modes.indices {
                for b in modes[index].bindings.indices where modes[index].bindings[b].action == .nextMode {
                    modes[index].bindings[b].action = .modeWheel
                }
            }
            if !modes.contains(where: \.isControlSurface) {
                modes.append(Self.controlMode)
            }
        }
        if schemaVersion < 3 {
            // 0.2: every mode but Normal is a surface; Media becomes a music surface.
            for index in modes.indices where modes[index].name == "Media" && !modes[index].isControlSurface {
                modes[index].surface = .music
                modes[index].bindings = []
                modes[index].appProfiles = []
            }
        }
        if schemaVersion < 4 {
            // The middle of the Media surface goes back, like Control.
            for index in modes.indices where modes[index].name == "Media" && modes[index].surface?.center == .nowPlaying {
                modes[index].surface?.center = .back
            }
        }
        if schemaVersion < 5 {
            // 0.2: tools join the mode wheel.
            for tool in ModeTool.allCases where !modes.contains(where: { $0.tool == tool }) {
                modes.append(tool.defaultMode)
            }
        }
        schemaVersion = Self.currentSchemaVersion
    }

    public var activeMode: Mode {
        get { modes.first { $0.id == activeModeID } ?? modes[0] }
        set {
            if let index = modes.firstIndex(where: { $0.id == newValue.id }) { modes[index] = newValue }
        }
    }

    /// The modes that use gesture bindings, i.e. not control surfaces.
    public var gestureModes: [Mode] { modes.filter { !$0.isOverlay } }

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
            GestureBinding(trigger: .tap(fingers: 4, count: 2, zone: .anywhere), action: .modeWheel),
        ])
        let media = Mode(name: "Media", symbol: "play.circle", surface: .music)
        return Configuration(modes: [normal, media, controlMode] + ModeTool.allCases.map(\.defaultMode))
    }

    static var controlMode: Mode {
        Mode(name: "Control", symbol: "slider.horizontal.below.square.and.square.filled", surface: ControlSurfaceLayout())
    }
}
