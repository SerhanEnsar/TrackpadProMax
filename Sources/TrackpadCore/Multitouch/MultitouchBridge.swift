import CMultitouch
import Foundation

/// Runtime binding to Apple's private MultitouchSupport.framework.
///
/// Symbols are looked up with `dlsym` so the app still launches (with reduced
/// features) if a future macOS removes or renames the framework.
final class MultitouchBridge: @unchecked Sendable {
    typealias DeviceRef = UnsafeMutableRawPointer
    typealias ContactCallback = @convention(c) (
        DeviceRef?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32
    ) -> Int32

    let createDefault: @convention(c) () -> DeviceRef?
    let createList: @convention(c) () -> Unmanaged<CFMutableArray>?
    let registerCallback: @convention(c) (DeviceRef, ContactCallback) -> Void
    let unregisterCallback: @convention(c) (DeviceRef, ContactCallback) -> Void
    let start: @convention(c) (DeviceRef, Int32) -> Void
    let stop: @convention(c) (DeviceRef) -> Void
    let isBuiltIn: @convention(c) (DeviceRef) -> Bool
    let getDeviceID: @convention(c) (DeviceRef, UnsafeMutablePointer<UInt64>) -> Int32

    let actuatorCreate: @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    let actuatorOpen: @convention(c) (CFTypeRef) -> Int32
    let actuatorClose: @convention(c) (CFTypeRef) -> Int32
    let actuatorActuate: @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// `nil` when the framework or any required symbol is missing.
    static let shared: MultitouchBridge? = MultitouchBridge()

    private init?() {
        guard let handle = dlopen(Self.path, RTLD_NOW) else { return nil }
        func load<T>(_ name: String, as _: T.Type = T.self) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard
            let createDefault: @convention(c) () -> DeviceRef? = load("MTDeviceCreateDefault"),
            let createList: @convention(c) () -> Unmanaged<CFMutableArray>? = load("MTDeviceCreateList"),
            let registerCallback: @convention(c) (DeviceRef, ContactCallback) -> Void = load("MTRegisterContactFrameCallback"),
            let unregisterCallback: @convention(c) (DeviceRef, ContactCallback) -> Void = load("MTUnregisterContactFrameCallback"),
            let start: @convention(c) (DeviceRef, Int32) -> Void = load("MTDeviceStart"),
            let stop: @convention(c) (DeviceRef) -> Void = load("MTDeviceStop"),
            let isBuiltIn: @convention(c) (DeviceRef) -> Bool = load("MTDeviceIsBuiltIn"),
            let getDeviceID: @convention(c) (DeviceRef, UnsafeMutablePointer<UInt64>) -> Int32 = load("MTDeviceGetDeviceID"),
            let actuatorCreate: @convention(c) (UInt64) -> Unmanaged<CFTypeRef>? = load("MTActuatorCreateFromDeviceID"),
            let actuatorOpen: @convention(c) (CFTypeRef) -> Int32 = load("MTActuatorOpen"),
            let actuatorClose: @convention(c) (CFTypeRef) -> Int32 = load("MTActuatorClose"),
            let actuatorActuate: @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32 = load("MTActuatorActuate")
        else { return nil }
        self.createDefault = createDefault
        self.createList = createList
        self.registerCallback = registerCallback
        self.unregisterCallback = unregisterCallback
        self.start = start
        self.stop = stop
        self.isBuiltIn = isBuiltIn
        self.getDeviceID = getDeviceID
        self.actuatorCreate = actuatorCreate
        self.actuatorOpen = actuatorOpen
        self.actuatorClose = actuatorClose
        self.actuatorActuate = actuatorActuate
    }

    /// All multitouch devices (built-in trackpad, Magic Trackpad, ...).
    /// The returned array owns the devices and must outlive their use.
    func deviceList() -> (list: CFMutableArray, devices: [DeviceRef])? {
        guard let list = createList()?.takeRetainedValue() else { return nil }
        let devices = (0..<CFArrayGetCount(list)).compactMap { index in
            CFArrayGetValueAtIndex(list, index).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        return (list, devices)
    }

    func deviceID(of device: DeviceRef) -> UInt64? {
        var id: UInt64 = 0
        return getDeviceID(device, &id) == 0 ? id : nil
    }
}
