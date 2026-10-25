import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import ObjectiveC

/// Reads and writes continuous system levels (0...1) for the control surface.
/// Values are set directly, not by simulating keys, so changes are smooth.
@MainActor
public enum SystemControls {
    public static func value(of control: SurfaceControl) -> Double? {
        switch control {
        case .volume: Volume.get()
        case .brightness: Brightness.get()
        case .keyboardBacklight: KeyboardBacklight.get()
        case .none, .media, .seek: nil
        }
    }

    /// Sets the level and returns what the system actually took.
    @discardableResult
    public static func set(_ control: SurfaceControl, to value: Double) -> Double? {
        let clamped = min(1, max(0, value))
        switch control {
        case .volume: Volume.set(clamped)
        case .brightness: Brightness.set(clamped)
        case .keyboardBacklight: KeyboardBacklight.set(clamped)
        case .none, .media, .seek: return nil
        }
        return Self.value(of: control)
    }
}

// MARK: - Volume (CoreAudio)

@MainActor
private enum Volume {
    static func defaultOutput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
    }

    static func get() -> Double? {
        guard let device = defaultOutput() else { return nil }
        var address = volumeAddress
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    static func set(_ value: Double) {
        guard let device = defaultOutput() else { return }
        var address = volumeAddress
        var volume = Float32(value)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        if status != noErr { Log.action.error("Set volume failed: \(status, privacy: .public)") }
        setMuted(value <= 0.001, device: device)
    }

    private static func setMuted(_ muted: Bool, device: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// MARK: - Display brightness (DisplayServices, private)

@MainActor
private enum Brightness {
    typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    static let getter: Get? = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Get.self) }
    static let setter: Set? = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Set.self) }

    /// The built-in panel if there is one, else the main display.
    static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count = UInt32(0)
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    static func get() -> Double? {
        guard let getter else { return nil }
        var value = Float(0)
        return getter(display, &value) == 0 ? Double(value) : nil
    }

    static func set(_ value: Double) {
        _ = setter?(display, Float(value))
    }
}

// MARK: - Keyboard backlight (CoreBrightness, private)

@MainActor
private enum KeyboardBacklight {
    typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    static var keyboardID: UInt64? {
        let ids = client?.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        return ids?.first?.uint64Value
    }

    static func get() -> Double? {
        guard let client, let id = keyboardID else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
        return Double(unsafeBitCast(imp, to: Get.self)(client, selector, id))
    }

    static func set(_ value: Double) {
        guard let client, let id = keyboardID else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: selector), let imp = client.method(for: selector) else { return }
        _ = unsafeBitCast(imp, to: Set.self)(client, selector, Float(value), id)
    }
}
