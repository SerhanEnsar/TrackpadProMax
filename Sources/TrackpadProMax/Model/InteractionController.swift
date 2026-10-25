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
    /// Force for hard presses on surface bars; follows the hard-press setting.
    var deepPressThreshold = 750.0
    var wheelIdleTimeout: TimeInterval = 8

    private(set) var isWheelOpen = false
    private(set) var surfaceMode: Mode?
    var isActive: Bool { isWheelOpen || surfaceMode != nil || toolMode != nil }

    private let pipeline: TouchPipeline
    private let inputLock = InputLock()
    private let input = OverlayInput()
    private let wheelPanel = OverlayPanel<ModeWheelView>(size: NSSize(width: 460, height: 460))
    private let surfacePanel = OverlayPanel<ControlSurfaceView>(size: NSSize(
        width: ControlSurfaceView.size.width + 60, height: ControlSurfaceView.size.height + 60
    ))
    private var idleTimer: Timer?
    private var nowPlayingTimer: Timer?
    /// While scrubbing, polled positions would yank the bar back; ignore them.
    private var scrubbingUntil = Date.distantPast
    /// Hardware writes are coalesced to ~30 Hz; touch frames arrive at ~100 Hz.
    private var pendingLevels: [SurfaceControl: Double] = [:]
    private var pendingDeviceVolumes: [AudioOutputDevice.ID: Double] = [:]
    private var writeScheduled = false
    private var adjustStep: [SurfaceEdge: Int] = [:]

    init(pipeline: TouchPipeline) {
        self.pipeline = pipeline
        inputLock.onEscape = { [weak self] in self?.escape() }
        input.onWheel = { [weak self] events, knob in self?.handleWheel(events, knob: knob) }
        input.onSurface = { [weak self] events in self?.handleSurface(events) }
        input.onActivity = { [weak self] in self?.restartIdleTimer() }
        input.onDevices = { [weak self] events in self?.handleDevices(events) }
        pipeline.setFrameTap { [input] frame in input.process(frame) }
    }

    // MARK: - Mode wheel

    enum WheelLevel { case main, gestures }
    private(set) var wheelLevel = WheelLevel.main
    private var wheelConfiguration: Configuration?
    private var wheelActiveID: UUID?

    func toggleWheel(configuration: Configuration, activeID: UUID) {
        isWheelOpen ? closeWheel() : openWheel(configuration: configuration, activeID: activeID)
    }

    func openWheel(configuration: Configuration, activeID: UUID) {
        guard !WheelMenu.main(configuration).isEmpty else { return }
        wheelConfiguration = configuration
        wheelActiveID = activeID
        isWheelOpen = true
        // The wheel replaces the surface on screen; cancelling brings it back.
        surfacePanel.hide()
        showWheelLevel(.main, waitForLift: !touchesAreUp)
        inputLock.engage()
        wheelPanel.show(ModeWheelView(state: state))
        HapticEngine.shared.play(.weak)
        restartIdleTimer()
    }

    /// Fills the wheel with the main menu or the gesture-mode folder.
    private func showWheelLevel(_ level: WheelLevel, waitForLift: Bool) {
        guard let configuration = wheelConfiguration else { return }
        wheelLevel = level
        let items = level == .main ? WheelMenu.main(configuration) : WheelMenu.gestures(configuration)
        let activeIsGesture = configuration.gestureModes.contains { $0.id == wheelActiveID }
        state.wheelItems = items
        state.wheelActive = items.firstIndex { item in
            switch item.target {
            case .gestureFolder: activeIsGesture
            case let .mode(id): id == wheelActiveID
            }
        }
        state.wheelTitle = level == .main ? "TrackPadPM" : WheelMenu.folderName
        state.wheelIsSubmenu = level == .gestures
        state.wheelHighlighted = nil
        state.wheelKnob = Point(x: 0, y: 0)
        input.install(.wheel(RadialSelector(itemCount: max(1, items.count))), waitForLift: waitForLift)
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
                let item = index.flatMap { state.wheelItems.indices.contains($0) ? state.wheelItems[$0] : nil }
                switch item?.target {
                case nil:
                    HapticEngine.shared.play(.weak)
                    if wheelLevel == .gestures {
                        // The folder's middle is Back.
                        showWheelLevel(.main, waitForLift: true)
                        restartIdleTimer()
                    } else {
                        closeWheel()
                    }
                case .gestureFolder:
                    HapticEngine.shared.play(.click)
                    showWheelLevel(.gestures, waitForLift: true)
                    restartIdleTimer()
                case let .mode(picked):
                    HapticEngine.shared.play(.click)
                    closeWheel(restoreSurface: false)
                    onSelectMode(picked)
                    // Picked the surface that was already active: show it again.
                    if surfaceMode != nil, !surfacePanel.isVisible { restoreSurfaceAfterWheel() }
                }
                return
            }
        }
        restartIdleTimer()
    }

    // MARK: - Tools

    private(set) var toolMode: Mode?

    func enterTool(_ mode: Mode) {
        guard let tool = mode.tool else { return }
        toolMode = mode
        Log.action.notice("Tool \(tool.rawValue, privacy: .public) is not available yet")
        onSurfaceIdle()
    }

    func exitTool() {
        guard toolMode != nil else { return }
        toolMode = nil
    }

    // MARK: - Control surface

    private func restoreSurfaceAfterWheel() {
        guard let surfaceMode else { return }
        state.surfaceName = surfaceMode.name
        input.install(.surface(newTracker()), waitForLift: true)
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
        startNowPlayingUpdates()
        inputLock.engage()
        if !isWheelOpen {
            input.install(.surface(newTracker()), waitForLift: !touchesAreUp)
            surfacePanel.show(ControlSurfaceView(state: state))
        }
        restartIdleTimer()
    }

    func exitSurface() {
        guard surfaceMode != nil else { return }
        surfaceMode = nil
        state.devicePicker = nil
        nowPlayingTimer?.invalidate()
        nowPlayingTimer = nil
        surfacePanel.hide()
        if !isWheelOpen {
            input.install(.none, waitForLift: false)
            inputLock.release()
            idleTimer?.invalidate()
        }
    }

    private func refreshSurfaceValues() {
        for edge in SurfaceEdge.allCases where state.surfaceLayout[edge] != .seek {
            state.surfaceValues[edge] = SystemControls.value(of: state.surfaceLayout[edge]) ?? 0
        }
    }

    // MARK: Now Playing

    private func startNowPlayingUpdates() {
        nowPlayingTimer?.invalidate()
        state.nowPlaying = nil
        guard state.surfaceLayout.isMusic else { return }
        refreshNowPlaying()
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNowPlaying() }
        }
    }

    private func refreshNowPlaying() {
        NowPlayingCenter.shared.fetch { [weak self] info in
            guard let self, self.surfaceMode != nil else { return }
            guard Date() > self.scrubbingUntil else { return }
            self.state.nowPlaying = info
            for edge in SurfaceEdge.allCases where self.state.surfaceLayout[edge] == .seek {
                self.state.surfaceValues[edge] = info?.progress ?? 0
            }
        }
    }

    /// One seek when the finger lifts: players apply it in one jump, and the
    /// poller resumes only after it had time to land.
    private func seek(to seconds: TimeInterval) {
        NowPlayingCenter.shared.seek(to: seconds, appBundleID: state.nowPlaying?.appBundleID) { [weak self] in
            self?.scrubbingUntil = Date().addingTimeInterval(0.6)
        }
    }

    private func scheduleWrite() {
        guard !writeScheduled else { return }
        writeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in self?.flushWrites() }
    }

    private func flushWrites() {
        writeScheduled = false
        for (control, value) in pendingLevels { SystemControls.set(control, to: value) }
        for (id, value) in pendingDeviceVolumes { AudioDevices.setVolume(value, for: id) }
        pendingLevels = [:]
        pendingDeviceVolumes = [:]
    }

    private func handleSurface(_ events: [ControlSurfaceTracker.Event]) {
        guard surfaceMode != nil, !isWheelOpen else { return }
        for event in events {
            switch event {
            case let .began(edge):
                state.activeEdge = edge
                if state.surfaceLayout[edge] == .seek {
                    state.surfaceValues[edge] = state.nowPlaying?.progress ?? 0
                } else {
                    state.surfaceValues[edge] = SystemControls.value(of: state.surfaceLayout[edge]) ?? 0
                }
                adjustStep[edge] = step(state.surfaceValues[edge] ?? 0)
            case let .adjust(edge, delta):
                let control = state.surfaceLayout[edge]
                guard control.isContinuous else { continue }
                let target = min(1, max(0, (state.surfaceValues[edge] ?? 0) + delta))
                state.surfaceValues[edge] = target
                if control == .seek {
                    guard let track = state.nowPlaying, track.duration > 0 else { continue }
                    // Hold off polled positions until the final seek has landed.
                    scrubbingUntil = .distantFuture
                    state.nowPlaying?.elapsed = target * track.duration
                } else {
                    pendingLevels[control] = target
                    scheduleWrite()
                }
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
                if state.surfaceLayout[edge] == .seek {
                    if let track = state.nowPlaying, track.duration > 0 {
                        seek(to: (state.surfaceValues[edge] ?? 0) * track.duration)
                    } else {
                        scrubbingUntil = .distantPast
                    }
                }
                flushWrites()
            case let .deepPress(edge):
                if state.surfaceLayout[edge] == .volume {
                    openDevicePicker()
                    return
                }
            case .centerTap:
                switch state.surfaceLayout.center {
                case .nowPlaying:
                    ActionPerformer.shared.perform(.system(.playPause))
                    HapticEngine.shared.play(.medium)
                    state.nowPlaying?.isPlaying.toggle()
                case .back:
                    HapticEngine.shared.play(.weak)
                    escape()
                    return
                }
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

    // MARK: Output devices

    private func openDevicePicker() {
        let devices = AudioDevices.outputs()
        guard !devices.isEmpty else { return }
        let current = devices.firstIndex(where: \.isDefault) ?? 0
        var volumes: [AudioOutputDevice.ID: Double] = [:]
        for device in devices { volumes[device.id] = AudioDevices.volume(of: device.id) ?? 0 }
        state.activeEdge = nil
        state.devicePicker = .init(devices: devices, highlighted: current, volumes: volumes)
        input.install(
            .devices(DevicePicker(itemCount: devices.count, highlighted: current, deepPressThreshold: deepPressThreshold)),
            waitForLift: true
        )
        HapticEngine.shared.play([.strong, .weak])
        restartIdleTimer()
    }

    private func closeDevicePicker() {
        guard state.devicePicker != nil else { return }
        state.devicePicker = nil
        refreshSurfaceValues()
        input.install(.surface(newTracker()), waitForLift: true)
        restartIdleTimer()
    }

    private func handleDevices(_ events: [DevicePicker.Event]) {
        guard var picker = state.devicePicker else { return }
        for event in events {
            switch event {
            case let .highlight(index):
                picker.highlighted = index
                HapticEngine.shared.play(.tick)
            case let .adjust(index, delta):
                let id = picker.devices[index].id
                let old = picker.volumes[id] ?? 0
                let value = min(1, max(0, old + delta))
                picker.volumes[id] = value
                pendingDeviceVolumes[id] = value
                scheduleWrite()
                if step(value) != step(old) { HapticEngine.shared.play(value <= 0 || value >= 1 ? .medium : .tick) }
            case let .activate(index):
                flushWrites()
                let id = picker.devices[index].id
                AudioDevices.makeDefault(id)
                for i in picker.devices.indices { picker.devices[i].isDefault = picker.devices[i].id == id }
                HapticEngine.shared.play(.heavyClick)
                Log.action.notice("Output switched to \(picker.devices[index].name, privacy: .public)")
            case .dismiss:
                state.devicePicker = picker
                closeDevicePicker()
                return
            }
        }
        state.devicePicker = picker
        restartIdleTimer()
    }

    private func newTracker() -> ControlSurfaceTracker {
        ControlSurfaceTracker(deepPressThreshold: deepPressThreshold)
    }

    private var touchesAreUp: Bool { pipeline.latestFrame.activeTouches.isEmpty }

    /// Same as pressing Esc: closes the wheel, or leaves the surface (and its
    /// device bars) entirely.
    func escape() {
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
        case devices(DevicePicker)
    }

    // Set once on the main actor before frames flow; only called on the main actor.
    var onWheel: @MainActor @Sendable ([RadialSelector.Event], Point) -> Void = { _, _ in }
    var onSurface: @MainActor @Sendable ([ControlSurfaceTracker.Event]) -> Void = { _ in }
    var onActivity: @MainActor @Sendable () -> Void = {}
    var onDevices: @MainActor @Sendable ([DevicePicker.Event]) -> Void = { _ in }

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
        case var .devices(picker):
            let events = picker.process(frame)
            kind = .devices(picker)
            lock.unlock()
            if !events.isEmpty {
                let callback = onDevices
                Task { @MainActor in callback(events) }
            } else if ping {
                let callback = onActivity
                Task { @MainActor in callback() }
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
