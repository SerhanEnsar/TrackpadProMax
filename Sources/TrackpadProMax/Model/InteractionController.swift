import AppKit
import TrackpadCore

/// Runs the two "the trackpad drives an overlay" interactions:
/// the radial mode wheel and control surface modes. While either is up the
/// cursor is frozen and touches go to the overlay instead of the Mac.
@MainActor
final class InteractionController {
    let state = OverlayState()

    /// The user picked a mode on the wheel.
    var onSelectMode: (UUID) -> Void = { _ in }
    /// The control surface went unused for `surfaceIdleTimeout`.
    var onSurfaceIdle: () -> Void = {}

    var surfaceIdleTimeout: TimeInterval = 5
    var wheelIdleTimeout: TimeInterval = 8

    private(set) var isWheelOpen = false
    private(set) var surfaceMode: Mode?
    var isActive: Bool { isWheelOpen || surfaceMode != nil }

    private let pipeline: TouchPipeline
    private let inputLock = InputLock()
    private let input = OverlayInput()
    private let wheelPanel = OverlayPanel<ModeWheelView>(size: NSSize(width: 460, height: 460))
    private let surfacePanel = OverlayPanel<ControlSurfaceView>(size: NSSize(
        width: ControlSurfaceView.size.width + 60, height: ControlSurfaceView.size.height + 60
    ))
    private var idleTimer: Timer?
    private var adjustStep: [SurfaceEdge: Int] = [:]

    init(pipeline: TouchPipeline) {
        self.pipeline = pipeline
        inputLock.onEscape = { [weak self] in self?.escape() }
        input.onWheel = { [weak self] events, knob in self?.handleWheel(events, knob: knob) }
        input.onSurface = { [weak self] events in self?.handleSurface(events) }
        input.onActivity = { [weak self] in self?.restartIdleTimer() }
        pipeline.setFrameTap { [input] frame in input.process(frame) }
    }

    // MARK: - Mode wheel

    func toggleWheel(modes: [Mode], activeID: UUID) {
        isWheelOpen ? closeWheel() : openWheel(modes: modes, activeID: activeID)
    }

    func openWheel(modes: [Mode], activeID: UUID) {
        guard !modes.isEmpty else { return }
        let active = modes.firstIndex { $0.id == activeID }
        state.wheelItems = modes.map { .init(id: $0.id, name: $0.name, symbol: $0.symbol) }
        state.wheelActive = active
        state.wheelHighlighted = nil
        state.wheelKnob = Point(x: 0, y: 0)
        isWheelOpen = true
        // The wheel replaces the surface on screen; cancelling brings it back.
        surfacePanel.hide()
        input.install(.wheel(RadialSelector(itemCount: modes.count)), waitForLift: !touchesAreUp)
        inputLock.engage()
        wheelPanel.show(ModeWheelView(state: state))
        HapticEngine.shared.play(.weak)
        restartIdleTimer()
    }

    /// `restoreSurface: false` when a mode was picked: the caller switches
    /// modes right after, so the old surface must not flash back.
    func closeWheel(restoreSurface: Bool = true) {
        guard isWheelOpen else { return }
        isWheelOpen = false
        wheelPanel.hide()
        if surfaceMode != nil {
            if restoreSurface {
                // Back to the surface the wheel was opened from.
                restoreSurfaceAfterWheel()
            } else {
                // Keep the lock: the caller is about to switch modes.
                input.install(.none, waitForLift: false)
            }
        } else {
            input.install(.none, waitForLift: false)
            inputLock.release()
            idleTimer?.invalidate()
        }
    }

    private func handleWheel(_ events: [RadialSelector.Event], knob: Point) {
        guard isWheelOpen else { return }
        state.wheelKnob = knob
        for event in events {
            switch event {
            case let .highlight(index):
                state.wheelHighlighted = index
                HapticEngine.shared.play(.tick)
            case let .confirm(index):
                let picked = index.flatMap { state.wheelItems.indices.contains($0) ? state.wheelItems[$0].id : nil }
                HapticEngine.shared.play(picked == nil ? .weak : .click)
                guard let picked else {
                    closeWheel()
                    return
                }
                closeWheel(restoreSurface: false)
                onSelectMode(picked)
                // Picked the surface that was already active: show it again.
                if surfaceMode != nil, !surfacePanel.isVisible { restoreSurfaceAfterWheel() }
                return
            }
        }
        restartIdleTimer()
    }

    // MARK: - Control surface

    private func restoreSurfaceAfterWheel() {
        guard let surfaceMode else { return }
        state.surfaceName = surfaceMode.name
        input.install(.surface(ControlSurfaceTracker()), waitForLift: true)
        surfacePanel.show(ControlSurfaceView(state: state))
        restartIdleTimer()
    }

    func enterSurface(_ mode: Mode) {
        guard let layout = mode.surface else { return }
        surfaceMode = mode
        state.surfaceName = mode.name
        state.surfaceLayout = layout
        state.activeEdge = nil
        refreshSurfaceValues()
        inputLock.engage()
        if !isWheelOpen {
            input.install(.surface(ControlSurfaceTracker()), waitForLift: !touchesAreUp)
            surfacePanel.show(ControlSurfaceView(state: state))
        }
        restartIdleTimer()
    }

    func exitSurface() {
        guard surfaceMode != nil else { return }
        surfaceMode = nil
        surfacePanel.hide()
        if !isWheelOpen {
            input.install(.none, waitForLift: false)
            inputLock.release()
            idleTimer?.invalidate()
        }
    }

    private func refreshSurfaceValues() {
        for edge in SurfaceEdge.allCases {
            state.surfaceValues[edge] = SystemControls.value(of: state.surfaceLayout[edge]) ?? 0
        }
    }

    private func handleSurface(_ events: [ControlSurfaceTracker.Event]) {
        guard surfaceMode != nil, !isWheelOpen else { return }
        for event in events {
            switch event {
            case let .began(edge):
                state.activeEdge = edge
                state.surfaceValues[edge] = SystemControls.value(of: state.surfaceLayout[edge]) ?? 0
                adjustStep[edge] = step(state.surfaceValues[edge] ?? 0)
            case let .adjust(edge, delta):
                let control = state.surfaceLayout[edge]
                guard control.isContinuous else { continue }
                let target = min(1, max(0, (state.surfaceValues[edge] ?? 0) + delta))
                state.surfaceValues[edge] = target
                SystemControls.set(control, to: target)
                let newStep = step(target)
                if newStep != adjustStep[edge] {
                    adjustStep[edge] = newStep
                    HapticEngine.shared.play(target <= 0 || target >= 1 ? .medium : .tick)
                }
            case let .tap(edge):
                if state.surfaceLayout[edge] == .media {
                    ActionPerformer.shared.perform(.system(.playPause))
                    flashMedia(edge, "playpause.fill")
                }
            case let .swipe(edge, direction):
                if state.surfaceLayout[edge] == .media {
                    ActionPerformer.shared.perform(.system(direction > 0 ? .nextTrack : .previousTrack))
                    flashMedia(edge, direction > 0 ? "forward.fill" : "backward.fill")
                }
            case let .ended(edge):
                if state.activeEdge == edge { state.activeEdge = nil }
            }
        }
        restartIdleTimer()
    }

    /// 16 haptic detents across the range, like the system volume steps.
    private func step(_ value: Double) -> Int { Int((value * 16).rounded()) }

    private func flashMedia(_ edge: SurfaceEdge, _ symbol: String) {
        HapticEngine.shared.play(.medium)
        state.mediaFeedback = (edge, symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.state.mediaFeedback?.symbol == symbol { self?.state.mediaFeedback = nil }
        }
    }

    // MARK: - Shared

    private var touchesAreUp: Bool { pipeline.latestFrame.activeTouches.isEmpty }

    private func escape() {
        if isWheelOpen {
            closeWheel()
        } else if surfaceMode != nil {
            onSurfaceIdle()
        }
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        let timeout = isWheelOpen ? wheelIdleTimeout : surfaceIdleTimeout
        idleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isWheelOpen {
                    self.closeWheel()
                } else if self.surfaceMode != nil {
                    self.onSurfaceIdle()
                }
            }
        }
    }
}

/// Feeds touch frames to the active overlay logic on the multitouch thread
/// and forwards only the results to the main actor.
private final class OverlayInput: @unchecked Sendable {
    enum Kind {
        case none
        case wheel(RadialSelector)
        case surface(ControlSurfaceTracker)
    }

    // Set once on the main actor before frames flow; only called on the main actor.
    var onWheel: @MainActor @Sendable ([RadialSelector.Event], Point) -> Void = { _, _ in }
    var onSurface: @MainActor @Sendable ([ControlSurfaceTracker.Event]) -> Void = { _ in }
    var onActivity: @MainActor @Sendable () -> Void = {}

    private let lock = NSLock()
    private var kind = Kind.none
    /// Ignore the touch that opened the overlay until all fingers lift.
    private var waitingForLift = false
    private var lastKnob = Point(x: 0, y: 0)
    private var lastActivity: TimeInterval = 0

    func install(_ kind: Kind, waitForLift: Bool) {
        lock.withLock {
            self.kind = kind
            waitingForLift = waitForLift
            lastKnob = Point(x: 0, y: 0)
        }
    }

    func process(_ frame: TouchFrame) {
        lock.lock()
        if waitingForLift {
            if frame.activeTouches.isEmpty { waitingForLift = false }
            lock.unlock()
            return
        }
        let touching = !frame.activeTouches.isEmpty
        var ping = false
        if touching, frame.timestamp - lastActivity > 0.5 {
            lastActivity = frame.timestamp
            ping = true
        }
        switch kind {
        case .none:
            lock.unlock()
        case var .wheel(selector):
            let events = selector.process(frame)
            let knob = selector.knob
            kind = .wheel(selector)
            let moved = knob != lastKnob
            lastKnob = knob
            lock.unlock()
            if !events.isEmpty || moved {
                let callback = onWheel
                Task { @MainActor in callback(events, knob) }
            }
        case var .surface(tracker):
            let events = tracker.process(frame)
            kind = .surface(tracker)
            lock.unlock()
            if !events.isEmpty {
                let callback = onSurface
                Task { @MainActor in callback(events) }
            } else if ping {
                let callback = onActivity
                Task { @MainActor in callback() }
            }
        }
    }
}
