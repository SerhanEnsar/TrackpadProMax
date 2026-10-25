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

    init(settings: GestureSettings, onGesture: @escaping @MainActor @Sendable (GestureEvent) -> Void) {
        recognizer = GestureRecognizer(settings: settings)
        self.onGesture = onGesture
    }

    var latestFrame: TouchFrame { lock.withLock { latest } }

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

    private func process(_ frame: TouchFrame) {
        let events = lock.withLock {
            latest = frame
            return recognizer.process(frame)
        }
        guard !events.isEmpty else { return }
        let onGesture = onGesture
        Task { @MainActor in events.forEach(onGesture) }
    }
}
