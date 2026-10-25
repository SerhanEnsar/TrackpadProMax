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

    func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        frozenAt = CGEvent(source: nil)?.location ?? .zero
        // Detach the cursor from mouse movement and hide it; the tap below is the backstop.
        CGAssociateMouseAndMouseCursorPosition(0)
        CursorVisibility.hide()
        startTap()
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
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        Log.action.notice("Input lock released")
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
            if isEngaged, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        default:
            break
        }
        guard isEngaged else { return event }
        if event.getIntegerValueField(.eventSourceUserData) == ClickGate.syntheticMarker { return event }
        // Only warp if the cursor actually escaped; warping on every event stutters.
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged {
            let p = event.location
            if abs(p.x - frozenAt.x) > 1 || abs(p.y - frozenAt.y) > 1 { CGWarpMouseCursorPosition(frozenAt) }
        }
        return nil
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
