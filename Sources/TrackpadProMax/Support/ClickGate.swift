import AppKit
import CoreGraphics
import TrackpadCore

/// Holds back the system click while a deeper press might still happen.
///
/// Where a medium/hard press is bound, the trackpad's mouse-down is swallowed
/// and kept until the user's intent is clear (see `ClickIntent`):
/// - a bound press fires → the click is dropped (the gesture "ate" it),
/// - force eases off or holds steady → the click is delivered right away,
/// - the pointer drags or the click ends first → the click is delivered.
///
/// Needs the Accessibility permission (active event tap).
@MainActor
final class ClickGate {
    private enum State {
        case idle
        /// Mouse-down swallowed, waiting to see how deep the press goes.
        case holding(down: CGEvent)
        /// A bound press fired; swallow the rest of this click.
        case consumed
    }

    /// Marks events we post ourselves so the tap lets them through.
    static let syntheticMarker: Int64 = 0x5450_4D58

    /// Decides at mouse-down time whether to hold the click.
    var shouldHold: () -> Bool = { false }
    /// Called when a click starts being held; the owner reports back via
    /// `releaseHeldClick()` once the user's intent is clear.
    var onHold: () -> Void = {}
    /// Told about every real trackpad click, including swallowed ones.
    var onPhysicalClick: () -> Void = {}

    private var state = State.idle
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Starts the event tap. Fails without Accessibility permission; call again later.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        ]
        var mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        mask |= 1 << Self.pressureEventType
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: clickGateCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.action.error("Could not create click event tap (Accessibility permission missing?)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.action.notice("Click gate started")
        return true
    }

    /// Called when a bound press gesture fires. Returns true if it swallowed a held click.
    @discardableResult
    func consumeHeldClick() -> Bool {
        guard case .holding = state else { return false }
        state = .consumed
        return true
    }

    /// The user eased off or is holding still: deliver the held mouse-down now.
    /// The real mouse-up then passes through untouched.
    func releaseHeldClick() {
        guard case .holding = state else { return }
        Log.action.notice("Held click released: eased off or held steady")
        release(then: nil)
    }

    /// NSEventTypePressure; not part of `CGEventType`.
    fileprivate static let pressureEventType: UInt32 = 34

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // We may have missed the mouse-up; never replay a stale down later.
            state = .idle
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return event
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return event }

        if type.rawValue == Self.pressureEventType {
            // Keep Force Click / Look Up out of a click we are holding or ate.
            if case .idle = state { return event }
            return nil
        }

        switch type {
        case .leftMouseDown, .rightMouseDown:
            onPhysicalClick()
            // A new down while holding means we missed the up: drop the stale
            // down rather than replaying it without a matching up.
            state = .idle
            guard shouldHold(), let copy = event.copy() else { return event }
            state = .holding(down: copy)
            Log.action.notice("Click held")
            onHold()
            return nil

        case .leftMouseDragged, .rightMouseDragged:
            switch state {
            case .holding:
                // Re-post the drag after the held down so they arrive in order.
                Log.action.notice("Held click released: drag")
                release(then: event)
                return nil
            case .consumed:
                return nil
            case .idle:
                return event
            }

        case .leftMouseUp, .rightMouseUp:
            let current = state
            state = .idle
            switch current {
            case .holding:
                Log.action.notice("Held click released: click ended")
                release(then: event)
                return nil
            case .consumed:
                return nil
            case .idle:
                return event
            }

        default:
            return event
        }
    }

    /// Replays the held mouse-down, then `next` (a drag or the mouse-up), in order.
    private func release(then next: CGEvent?) {
        if case let .holding(down) = state { post(down) }
        state = .idle
        if let next { post(next) }
    }

    private func post(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cgSessionEventTap)
    }
}

private let clickGateCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let gate = Unmanaged<ClickGate>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so this is the main thread.
    nonisolated(unsafe) let input = event
    nonisolated(unsafe) var output: CGEvent?
    MainActor.assumeIsolated { output = gate.handle(type, input) }
    return output.map { Unmanaged.passUnretained($0) }
}
