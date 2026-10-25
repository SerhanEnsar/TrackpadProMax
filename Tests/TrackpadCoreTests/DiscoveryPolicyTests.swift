import Foundation
import Testing
@testable import TrackpadCore

@Suite struct DiscoveryPolicyTests {
    let safari = "com.apple.Safari"
    let global = GestureBinding(trigger: .tap(fingers: 3, count: 1, zone: .anywhere), action: .mouseClick(.middle))
    let own = GestureBinding(trigger: .press(tier: .hard, fingers: 1, zone: .topLeft), action: .system(.showDesktop))

    var mode: Mode {
        Mode(name: "M", symbol: "x", bindings: [global],
             appProfiles: [AppProfile(bundleID: safari, appName: "Safari", bindings: [own])])
    }

    @Test func showsOncePerProcess() {
        var policy = DiscoveryPolicy()
        let settings = DiscoverySettings()
        #expect(policy.gesturesToAnnounce(bundleID: safari, processID: 10, mode: mode, settings: settings) == [own, global])
        #expect(policy.gesturesToAnnounce(bundleID: safari, processID: 10, mode: mode, settings: settings) == nil)
        #expect(policy.gesturesToAnnounce(bundleID: safari, processID: 11, mode: mode, settings: settings) != nil,
                "relaunched app shows again")
    }

    @Test func defaultScopeSkipsAppsWithOnlyGlobalGestures() {
        var policy = DiscoveryPolicy()
        #expect(policy.gesturesToAnnounce(bundleID: "com.apple.Terminal", processID: 1, mode: mode, settings: DiscoverySettings()) == nil)
        var all = DiscoverySettings()
        all.scope = .allApps
        #expect(policy.gesturesToAnnounce(bundleID: "com.apple.Terminal", processID: 2, mode: mode, settings: all) == [global])
    }

    @Test func mutedAndDisabled() {
        var policy = DiscoveryPolicy()
        var muted = DiscoverySettings()
        muted.mutedApps = [safari]
        #expect(policy.gesturesToAnnounce(bundleID: safari, processID: 1, mode: mode, settings: muted) == nil)
        var off = DiscoverySettings()
        off.isEnabled = false
        #expect(policy.gesturesToAnnounce(bundleID: safari, processID: 2, mode: mode, settings: off) == nil)
    }

    @Test func oldConfigWithoutDiscoveryGetsDefaults() throws {
        var config = Configuration.defaults
        config.discovery.isEnabled = false
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        json["discovery"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(Configuration.self, from: data).discovery == DiscoverySettings())
    }
}
