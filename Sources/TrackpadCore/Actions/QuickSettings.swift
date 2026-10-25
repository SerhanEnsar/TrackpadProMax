import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import Foundation
import IOKit.pwr_mgt
import ObjectiveC

/// Reads and flips the switches on the Quick Settings grid.
@MainActor
public enum QuickSettings {
    /// Current state, or nil if it cannot be read (or the toggle is an action).
    public static func isOn(_ toggle: QuickToggle) -> Bool? {
        switch toggle {
        case .darkMode: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .nightShift: NightShift.isOn
        case .keepAwake: keepAwakeAssertion != nil
        case .wifi: CWWiFiClient.shared().interface()?.powerOn()
        case .bluetooth: Bluetooth.isOn
        case .mute: AudioMute.isMuted(input: false)
        case .micMute: AudioMute.isMuted(input: true)
        case .lockScreen: nil
        }
    }

    public static func toggle(_ toggle: QuickToggle) {
        let on = isOn(toggle) ?? false
        switch toggle {
        case .darkMode:
            // Needs Automation permission for System Events (asked once).
            runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .nightShift: NightShift.set(!on)
        case .keepAwake: setKeepAwake(!on)
        case .wifi:
            do {
                try CWWiFiClient.shared().interface()?.setPower(!on)
            } catch {
                Log.action.error("Wi-Fi toggle failed: \(error.localizedDescription, privacy: .public)")
            }
        case .bluetooth: Bluetooth.set(!on)
        case .mute: AudioMute.set(!on, input: false)
        case .micMute: AudioMute.set(!on, input: true)
        case .lockScreen: ActionPerformer.shared.perform(.system(.lockScreen))
        }
    }

    // MARK: Keep Awake

    private static var keepAwakeAssertion: IOPMAssertionID?

    private static func setKeepAwake(_ on: Bool) {
        if on {
            var id = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "TrackpadProMax Keep Awake" as CFString, &id
            )
            if status == kIOReturnSuccess { keepAwakeAssertion = id }
        } else if let id = keepAwakeAssertion {
            IOPMAssertionRelease(id)
            keepAwakeAssertion = nil
        }
    }

    private static func runAppleScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        try? process.run()
    }
}

// MARK: - Night Shift (CoreBrightness, private)

@MainActor
private enum NightShift {
    static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    /// `getBlueLightStatus:` fills a struct whose second byte is "enabled".
    static var isOn: Bool? {
        guard let client else { return nil }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
        typealias Get = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        var status = [UInt8](repeating: 0, count: 64)
        let ok = status.withUnsafeMutableBytes { unsafeBitCast(imp, to: Get.self)(client, selector, $0.baseAddress!) }
        return ok ? status[1] != 0 : nil
    }

    static func set(_ on: Bool) {
        guard let client else { return }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector), let imp = client.method(for: selector) else { return }
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(imp, to: Set.self)(client, selector, on)
    }
}

// MARK: - Bluetooth (IOBluetooth, private C API)

@MainActor
private enum Bluetooth {
    typealias Get = @convention(c) () -> Int32
    typealias Set = @convention(c) (Int32) -> Void

    static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)
    static let getter = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState").map { unsafeBitCast($0, to: Get.self) }
    static let setter = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState").map { unsafeBitCast($0, to: Set.self) }

    static var isOn: Bool? { getter.map { $0() != 0 } }

    static func set(_ on: Bool) { setter?(on ? 1 : 0) }
}

// MARK: - Output / microphone mute (CoreAudio)

@MainActor
private enum AudioMute {
    /// Input volume before muting a mic that has no mute switch.
    static var savedInputVolume: Float32?

    static func device(input: Bool) -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    static func address(_ selector: AudioObjectPropertySelector, input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func isMuted(input: Bool) -> Bool? {
        guard let id = device(input: input) else { return nil }
        var mute = address(kAudioDevicePropertyMute, input: input)
        if AudioObjectHasProperty(id, &mute) {
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &mute, 0, nil, &size, &value) == noErr else { return nil }
            return value != 0
        }
        return input ? savedInputVolume != nil : nil
    }

    static func set(_ muted: Bool, input: Bool) {
        guard let id = device(input: input) else { return }
        var mute = address(kAudioDevicePropertyMute, input: input)
        if AudioObjectHasProperty(id, &mute) {
            var value = UInt32(muted ? 1 : 0)
            AudioObjectSetPropertyData(id, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            return
        }
        // Mics without a mute switch: drop the input volume to zero and restore it later.
        guard input else { return }
        var volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, input: true)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if muted {
            AudioObjectGetPropertyData(id, &volumeAddress, 0, nil, &size, &volume)
            savedInputVolume = volume
            volume = 0
        } else {
            volume = savedInputVolume ?? 0.75
            savedInputVolume = nil
        }
        AudioObjectSetPropertyData(id, &volumeAddress, 0, nil, size, &volume)
    }
}
