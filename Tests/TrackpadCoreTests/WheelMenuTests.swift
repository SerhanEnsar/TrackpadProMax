import Foundation
import Testing
@testable import TrackpadCore

@Suite struct WheelMenuTests {
    @Test func mainWheelHasFolderThenOverlays() {
        let config = Configuration.defaults
        let names = WheelMenu.main(config).map(\.name)
        #expect(names == ["Normal", "Media", "Control", "Windows", "Apps", "Timer", "Quick Settings"])
        #expect(WheelMenu.main(config).first?.target == .gestureFolder)
    }

    @Test func folderListsGestureModes() {
        var config = Configuration.defaults
        config.modes.append(Mode(name: "Coding", symbol: "terminal"))
        #expect(WheelMenu.gestures(config).map(\.name) == ["Normal", "Coding"])
    }

    @Test func noGestureModesMeansNoFolder() {
        let config = Configuration(modes: [Mode(name: "Only", symbol: "x", tool: .timer)])
        #expect(WheelMenu.main(config).map(\.name) == ["Only"])
    }

    @Test func v4ConfigGetsToolModes() throws {
        var old = Configuration(modes: [Mode(name: "Normal", symbol: "hand.point.up.left")])
        old.schemaVersion = 4
        let config = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(old))
        #expect(Set(config.modes.compactMap(\.tool)) == Set(ModeTool.allCases))
        #expect(config.gestureModes.map(\.name) == ["Normal"])
    }
}
