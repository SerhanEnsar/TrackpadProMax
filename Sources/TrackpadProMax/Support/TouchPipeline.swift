import Foundation
import TrackpadCore

/// Runs gesture recognition on the multitouch callback thread and forwards
/// only recognized gestures to the main actor. The latest frame is kept for the
/// visualizer, which polls it at display rate instead of being pushed 100+ Hz.
final class TouchPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizer: GestureRecognizer
    private var latest = TouchFrame(timestamp: 0, touches: [])
    private var token: UUID?
    private let onGesture: @MainActor @Sendable (GestureEvent) -> Void
    private var clickIntent: ClickIntent?
    private var frameTap: (@Sendable (TouchFrame) -> Void)?
    private var onClickIntent: (@MainActor @Sendable (ClickIntent.Decision) -> Void)?

    init(settings: GestureSettings, onGesture: @escaping @MainActor @Sendable (GestureEvent) -> Void) {
        recognizer = GestureRecognizer(settings: settings)
        self.onGesture = onGesture
    }

    var latestFrame: TouchFrame { lock.withLock { latest } }

    /// Forwards a system mouse-down so the recognizer can tell clicks from taps.
    func registerPhysicalClick() {
        lock.withLock { recognizer.registerPhysicalClick() }
    }

    /// Starts judging a held click against `target` force. `decided` runs once on
    /// the main actor with the outcome.
    func watchClickIntent(target: Double, decided: @escaping @MainActor @Sendable (ClickIntent.Decision) -> Void) {
        lock.withLock {
            clickIntent = ClickIntent(target: target)
            onClickIntent = decided
        }
    }

    /// Also hands every frame to `tap` (on the multitouch thread) while set.
    func setFrameTap(_ tap: (@Sendable (TouchFrame) -> Void)?) {
        lock.withLock { frameTap = tap }
    }

    func stopWatchingClickIntent() {
        lock.withLock {
            clickIntent = nil
            onClickIntent = nil
        }
    }

    var settings: GestureSettings {
        get { lock.withLock { recognizer.settings } }
        set { lock.withLock { recognizer.settings = newValue } }
    }

    func start() {
        guard token == nil else { return }
        token = TouchStream.shared.addHandler { [weak self] frame in self?.process(frame) }
    }

    func stop() {
        if let token { TouchStream.shared.removeHandler(token) }
        token = nil
    }

    // Per-touch-session stats, logged on lift to help calibrate thresholds.
    private var sessionStart: TimeInterval?
    private var sessionFingers = 0
    private var sessionPeak = 0.0
    private var sessionStates: Set<Int> = []
    private var sessionMovement = 0.0

    private func process(_ frame: TouchFrame) {
        let (events, decision, decided, tap) = lock.withLock {
            latest = frame
            trackSession(frame)
            let events = recognizer.process(frame)
            var decision: ClickIntent.Decision?
            var decided: (@MainActor @Sendable (ClickIntent.Decision) -> Void)?
            if clickIntent != nil {
                let force = frame.activeTouches.map(\.pressure).max() ?? 0
                decision = clickIntent?.update(force: force, at: frame.timestamp)
                if decision != nil {
                    decided = onClickIntent
                    clickIntent = nil
                    onClickIntent = nil
                }
            }
            return (events, decision, decided, frameTap)
        }
        tap?(frame)
        if let decision, let decided {
            Task { @MainActor in decided(decision) }
        }
        for event in events {
            Log.gesture.notice("Recognized \(event.trigger.displayName, privacy: .public)")
        }
        guard !events.isEmpty else { return }
        let onGesture = onGesture
        Task { @MainActor in events.forEach(onGesture) }
    }

    /// `defaults write io.github.serhanensar.TrackpadProMax VerboseTouchLogging -bool YES`
    private let verbose = UserDefaults.standard.bool(forKey: "VerboseTouchLogging")

    private func trackSession(_ frame: TouchFrame) {
        if verbose, !frame.touches.isEmpty {
            let text = frame.touches.map {
                "#\($0.id) s\($0.phase.rawValue) (\(String(format: "%.3f,%.3f", $0.position.x, $0.position.y))) f\(Int($0.pressure))"
            }.joined(separator: " ")
            Log.touch.info("\(String(format: "%.3f", frame.timestamp), privacy: .public) \(text, privacy: .public)")
        }
        sessionStates.formUnion(frame.touches.map(\.phase.rawValue))
        let active = frame.activeTouches
        if active.isEmpty {
            guard let start = sessionStart else { return }
            Log.touch.notice("""
            Touch session: \(self.sessionFingers, privacy: .public) finger(s), \
            \(Int((frame.timestamp - start) * 1000), privacy: .public) ms, \
            peak force \(Int(self.sessionPeak), privacy: .public), \
            movement \(String(format: "%.3f", self.sessionMovement), privacy: .public), \
            states \(self.sessionStates.sorted().description, privacy: .public)
            """)
            sessionStart = nil
            return
        }
        if sessionStart == nil {
            sessionStart = frame.timestamp
            sessionFingers = 0
            sessionPeak = 0
            sessionStates = []
            sessionMovement = 0
        }
        sessionFingers = max(sessionFingers, active.count)
        sessionPeak = max(sessionPeak, active.map(\.pressure).max() ?? 0)
        sessionMovement = max(sessionMovement, recognizer.currentMovement)
    }
}
