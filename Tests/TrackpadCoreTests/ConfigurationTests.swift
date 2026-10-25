import Foundation
import Testing
@testable import TrackpadCore

@Suite struct ConfigurationTests {
    @Test func specificZoneBeatsAnywhere() {
        let mode = Mode(name: "T", symbol: "x", bindings: [
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .anywhere), action: .system(.mute)),
            GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .topLeft), action: .system(.showDesktop)),
        ])
        #expect(mode.binding(for: .press(tier: .hard, fingers: 1, zone: .topLeft), bundleID: nil)?.action == .system(.showDesktop))
        #expect(mode.binding(for: .press(tier: .hard, fingers: 1, zone: .center), bundleID: nil)?.action == .system(.mute))
    }

    @Test func appProfileOverridesGlobal() {
        let trigger = Trigger.tap(fingers: 3, count: 1, zone: .anywhere)
        let mode = Mode(
            name: "T", symbol: "x",
            bindings: [GestureBinding(trigger: trigger, action: .mouseClick(.middle))],
            appProfiles: [AppProfile(bundleID: "com.apple.Safari", appName: "Safari", bindings: [
                GestureBinding(trigger: trigger, action: .keyboardShortcut(KeyCombo(keyCode: 17, modifiers: 0))),
            ])]
        )
        #expect(mode.binding(for: trigger, bundleID: "com.apple.Safari")?.action == .keyboardShortcut(KeyCombo(keyCode: 17, modifiers: 0)))
        #expect(mode.binding(for: trigger, bundleID: "com.apple.Terminal")?.action == .mouseClick(.middle))
    }

    @Test func disabledBindingIsIgnored() {
        let trigger = Trigger.tap(fingers: 3, count: 1, zone: .anywhere)
        let mode = Mode(name: "T", symbol: "x", bindings: [
            GestureBinding(trigger: trigger, action: .mouseClick(.middle), isEnabled: false),
        ])
        #expect(mode.binding(for: trigger, bundleID: nil) == nil)
    }

    @Test func nextModeWraps() {
        var config = Configuration.defaults
        let first = config.activeModeID
        for _ in config.modes { config.selectNextMode() }
        #expect(config.activeModeID == first)
    }

    @Test func roundTripsThroughStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let store = ConfigurationStore(url: url)
        var config = Configuration.defaults
        config.gestures.hardThreshold = 999
        config.selectNextMode()
        try store.save(config)
        #expect(store.load() == config)
    }

    @Test func brokenFileFallsBackToDefaultsAndKeepsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.json")
        try Data("not json".utf8).write(to: url)
        let loaded = ConfigurationStore(url: url).load()
        #expect(loaded.modes.map(\.name) == Configuration.defaults.modes.map(\.name))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.broken.json").path))
    }

    @Test func oldFileWithoutNewKeysStillLoads() throws {
        let json = """
        {"modes":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Only","symbol":"star","bindings":[],"appProfiles":[]}],
         "activeModeID":"6F9619FF-8B86-D011-B42D-00C04FC964FF",
         "gestures":{"lightThreshold":60,"mediumThreshold":220,"hardThreshold":420,"releaseRatio":0.7,
                     "maxTapDuration":0.22,"maxTapMovement":0.03,"maxPressMovement":0.06,
                     "doubleTapInterval":0.3,"zoneMargin":0.18}}
        """
        let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(config.modes.map(\.name).prefix(2) == ["Only", "Control"], "migration adds the Control surface, then tools")
        #expect(config.gestures == GestureSettings(), "pre-0.1 default thresholds are migrated")
        #expect(config.modeHotkey == Configuration.defaults.modeHotkey)
        #expect(config.schemaVersion == Configuration.currentSchemaVersion)
    }

    @Test func customThresholdsSurviveMigration() throws {
        var old = Configuration.defaults
        old.gestures.hardThreshold = 999
        old.schemaVersion = 0
        let data = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(Configuration.self, from: data).gestures.hardThreshold == 999)
    }

    @Test func v1ConfigMigratesToWheelAndControlMode() throws {
        var old = Configuration(modes: [Mode(name: "Mine", symbol: "star", bindings: [
            GestureBinding(trigger: .tap(fingers: 4, count: 2, zone: .anywhere), action: .nextMode),
        ])])
        old.schemaVersion = 1
        let config = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(old))
        #expect(config.modes[0].bindings[0].action == .modeWheel)
        #expect(config.modes.filter(\.isControlSurface).count == 1)
        #expect(config.gestureModes.map(\.name) == ["Mine"])
    }

    @Test func surfaceLayoutRoundTrips() throws {
        var config = Configuration.defaults
        let index = config.modes.firstIndex(where: \.isControlSurface)!
        config.modes[index].surface?.top = .volume
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded.modes[index].surface?.top == .volume)
    }

    @Test func v2MediaGestureModeBecomesMusicSurface() throws {
        var old = Configuration(modes: [
            Mode(name: "Normal", symbol: "hand.point.up.left"),
            Mode(name: "Media", symbol: "play.circle", bindings: [
                GestureBinding(trigger: .tap(fingers: 3, count: 1, zone: .anywhere), action: .system(.mute)),
            ]),
        ])
        old.schemaVersion = 2
        let config = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(old))
        let media = try #require(config.modes.first { $0.name == "Media" })
        #expect(media.surface == .music)
        #expect(media.bindings.isEmpty)
        #expect(media.id == old.modes[1].id)
        #expect(config.gestureModes.map(\.name) == ["Normal"])
    }

    @Test func defaultsHaveOneGestureMode() {
        #expect(Configuration.defaults.gestureModes.map(\.name) == ["Normal"])
        #expect(Configuration.defaults.modes.map(\.name) == ["Normal", "Media", "Control", "Windows", "Apps", "Quick Settings"])
    }

    @Test func v3MediaMiddleBecomesBack() throws {
        var old = Configuration.defaults
        let index = old.modes.firstIndex { $0.name == "Media" }!
        old.modes[index].surface?.center = .nowPlaying
        old.schemaVersion = 3
        let config = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(old))
        #expect(config.modes[index].surface?.center == .back)
    }
}
