import AppKit
import CoreGraphics
import TrackpadCore

/// While an overlay (mode wheel, control surface) is up, the trackpad drives
/// the overlay instead of the Mac: the cursor is frozen and clicks, scrolls
/// and system gestures are swallowed. Escape closes the overlay.
@MainActor
final class InputLock {
    private(set) var isEngaged = false
    var onEscape: () -> Void = {}

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var frozenAt = CGPoint.zero
    private var keyMonitors: [Any] = []
    /// After release, clicks are still swallowed for a moment: the tap that
    /// closed the overlay turns into a tap-to-click only after the finger
    /// lifts, and that click must not land on the window underneath.
    private var drainUntil: Date?
    private var drainTimer: Timer?
    private var buttonsHeld = Set<CGEventType>()
    private static let drainDuration: TimeInterval = 0.35

    func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        stopDrain()
        frozenAt = CGEvent(source: nil)?.location ?? .zero
        // Detach the cursor from mouse movement and hide it; the tap below is the backstop.
        CGAssociateMouseAndMouseCursorPosition(0)
        CursorVisibility.hide()
        if tap == nil { startTap() }
        let escape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            MainActor.assumeIsolated { self?.onEscape() }
            return true
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = escape($0) }) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { escape($0) ? nil : $0 }) {
            keyMonitors.append(local)
        }
        Log.action.notice("Input lock engaged")
    }

    func release() {
        guard isEngaged else { return }
        isEngaged = false
        CGAssociateMouseAndMouseCursorPosition(1)
        CursorVisibility.show()
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        drainUntil = Date().addingTimeInterval(Self.drainDuration)
        drainTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishDrainIfDone() }
        }
        Log.action.notice("Input lock released")
    }

    /// Removes the tap once the grace period is over and no swallowed
    /// button is still waiting for its release (capped at 2 s).
    private func finishDrainIfDone() {
        guard let drainUntil else { return stopDrain() }
        let now = Date()
        if now < drainUntil { return }
        if !buttonsHeld.isEmpty, now < drainUntil.addingTimeInterval(2) { return }
        stopDrain()
        removeTap()
        buttonsHeld = []
    }

    private func stopDrain() {
        drainTimer?.invalidate()
        drainTimer = nil
        drainUntil = nil
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
    }

    private func startTap() {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
        ]
        var mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // Gesture (29), magnify (30), swipe (31), rotate (18), pressure (34), smart magnify (32)
        for raw: UInt64 in [18, 29, 30, 31, 32, 34] { mask |= 1 << raw }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: inputLockCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.action.error("Input lock tap failed (Accessibility permission?)")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isEngaged || drainUntil != nil, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == ClickGate.syntheticMarker { return event }
        guard isEngaged else { return drain(type, event) }
        // Remember swallowed presses so their releases are swallowed too, even after release().
        switch type {
        case .leftMouseDown: buttonsHeld.insert(.leftMouseUp)
        case .rightMouseDown: buttonsHeld.insert(.rightMouseUp)
        case .otherMouseDown: buttonsHeld.insert(.otherMouseUp)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: buttonsHeld.remove(type)
        default: break
        }
        // Only warp if the cursor actually escaped; warping on every event stutters.
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged {
            let p = event.location
            if abs(p.x - frozenAt.x) > 1 || abs(p.y - frozenAt.y) > 1 { CGWarpMouseCursorPosition(frozenAt) }
        }
        return nil
    }

    /// Just after release: swallow new button presses during the grace
    /// period, and the releases of any press that was swallowed.
    private func drain(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard let drainUntil else { return event }
        let pairs: [CGEventType: CGEventType] = [
            .leftMouseDown: .leftMouseUp, .rightMouseDown: .rightMouseUp, .otherMouseDown: .otherMouseUp,
        ]
        if let up = pairs[type], Date() < drainUntil {
            buttonsHeld.insert(up)
            Log.action.debug("Swallowed click after overlay closed")
            return nil
        }
        if buttonsHeld.contains(type) {
            buttonsHeld.remove(type)
            return nil
        }
        if type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged,
           !buttonsHeld.isEmpty {
            return nil
        }
        return event
    }
}

private let inputLockCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let lock = Unmanaged<InputLock>.fromOpaque(userInfo).takeUnretainedValue()
    nonisolated(unsafe) let input = event
    nonisolated(unsafe) var output: CGEvent?
    MainActor.assumeIsolated { output = lock.handle(type, input) }
    return output.map { Unmanaged.passUnretained($0) }
}

/// Hides the cursor even though TrackpadProMax is a background app.
///
/// `CGDisplayHideCursor` only works for the frontmost app unless the
/// connection has the (private) "SetsCursorInBackground" property.
@MainActor
enum CursorVisibility {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static var hidden = false

    private static let enableBackgroundCursor: Void = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_NOW),
              let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        _ = unsafeBitCast(setSym, to: SetProperty.self)(
            connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue
        )
    }()

    static func hide() {
        guard !hidden else { return }
        _ = enableBackgroundCursor
        CGDisplayHideCursor(CGMainDisplayID())
        hidden = true
    }

    static func show() {
        guard hidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        hidden = false
    }
}
