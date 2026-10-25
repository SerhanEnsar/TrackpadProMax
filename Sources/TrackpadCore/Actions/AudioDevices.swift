import AudioToolbox
import CoreAudio
import Foundation

/// An audio output: built-in speakers, AirPods, a Bluetooth or USB speaker…
public struct AudioOutputDevice: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case builtIn, bluetooth, airPlay, external, virtual
    }

    public let id: AudioDeviceID
    public let name: String
    public let kind: Kind
    public var isDefault: Bool

    public var symbol: String {
        let lower = name.lowercased()
        switch kind {
        case .builtIn: return "laptopcomputer"
        case .bluetooth:
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("beats") || lower.contains("headphone") || lower.contains("kulaklık") { return "headphones" }
            return "hifispeaker.fill"
        case .airPlay: return "airplayaudio"
        case .external: return lower.contains("display") || lower.contains("hdmi") ? "tv" : "speaker.wave.2.fill"
        case .virtual: return "waveform"
        }
    }
}

/// Lists output devices, reads/sets each one's volume and switches the
/// system output. Public CoreAudio only.
@MainActor
public enum AudioDevices {
    public static func outputs() -> [AudioOutputDevice] {
        let defaultID = defaultOutput()
        return deviceIDs().compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name, kind: kind(of: id), isDefault: id == defaultID)
        }
    }

    public static func volume(of id: AudioDeviceID) -> Double? {
        var address = volumeAddress
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    public static func setVolume(_ value: Double, for id: AudioDeviceID) {
        var address = volumeAddress
        guard AudioObjectHasProperty(id, &address) else { return }
        var volume = Float32(min(1, max(0, value)))
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        if status != noErr { Log.action.error("Set volume on device \(id, privacy: .public) failed: \(status, privacy: .public)") }
    }

    /// Routes all sound (and alerts) to `id`.
    public static func makeDefault(_ id: AudioDeviceID) {
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device)
            if status != noErr { Log.action.error("Switch output failed: \(status, privacy: .public)") }
        }
    }

    // MARK: - Helpers

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func kind(of id: AudioDeviceID) -> AudioOutputDevice.Kind {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return .external }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        default: return .external
        }
    }
}
