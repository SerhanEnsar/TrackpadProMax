import CMultitouch
import Foundation

/// Streams raw multitouch frames from every connected trackpad.
///
/// The private framework calls back on its own high-priority thread at the
/// device rate (~90-125 Hz). Handlers are invoked on that thread; hop to the
/// main actor yourself if you touch UI.
public final class TouchStream: @unchecked Sendable {
    public typealias Handler = @Sendable (TouchFrame) -> Void

    public static let shared = TouchStream()

    /// False when MultitouchSupport could not be loaded on this system.
    public var isAvailable: Bool { MultitouchBridge.shared != nil }
    public private(set) var isRunning = false

    private let lock = NSLock()
    private var handlers: [UUID: Handler] = [:]
    private var deviceList: CFMutableArray?
    private var devices: [MultitouchBridge.DeviceRef] = []

    private init() {}

    /// Registers a handler and starts the devices if needed. Keep the token to remove it.
    @discardableResult
    public func addHandler(_ handler: @escaping Handler) -> UUID {
        let token = UUID()
        lock.withLock { handlers[token] = handler }
        start()
        return token
    }

    public func removeHandler(_ token: UUID) {
        let empty = lock.withLock {
            handlers[token] = nil
            return handlers.isEmpty
        }
        if empty { stop() }
    }

    public func start() {
        guard let bridge = MultitouchBridge.shared else {
            Log.touch.error("MultitouchSupport unavailable")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning, let found = bridge.deviceList() else { return }
        deviceList = found.list
        devices = found.devices
        for device in devices {
            bridge.registerCallback(device, touchStreamCallback)
            bridge.start(device, 0)
        }
        isRunning = true
        Log.touch.notice("Started \(self.devices.count, privacy: .public) multitouch device(s)")
    }

    public func stop() {
        guard let bridge = MultitouchBridge.shared else { return }
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        for device in devices {
            bridge.unregisterCallback(device, touchStreamCallback)
            bridge.stop(device)
        }
        devices = []
        deviceList = nil
        isRunning = false
    }

    fileprivate func dispatch(_ frame: TouchFrame) {
        let current = lock.withLock { Array(handlers.values) }
        for handler in current { handler(frame) }
    }
}

extension Touch {
    init(_ raw: MTTouch) {
        self.init(
            id: Int(raw.identifier),
            phase: TouchPhase(rawValue: Int(raw.state)) ?? .notTracking,
            position: Point(x: Double(raw.normalized.position.x), y: Double(raw.normalized.position.y)),
            velocity: Point(x: Double(raw.normalized.velocity.x), y: Double(raw.normalized.velocity.y)),
            pressure: Double(raw.pressure),
            size: Double(raw.total),
            angle: Double(raw.angle),
            majorAxis: Double(raw.majorAxis),
            minorAxis: Double(raw.minorAxis)
        )
    }
}

private let touchStreamCallback: MultitouchBridge.ContactCallback = { _, touches, count, timestamp, _ in
    let buffer = UnsafeBufferPointer(start: touches, count: max(0, Int(count)))
    TouchStream.shared.dispatch(TouchFrame(timestamp: timestamp, touches: buffer.map(Touch.init)))
    return 0
}
