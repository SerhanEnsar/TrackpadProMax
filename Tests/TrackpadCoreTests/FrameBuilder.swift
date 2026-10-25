@testable import TrackpadCore

/// Builds synthetic input sequences at 100 Hz.
struct FrameBuilder {
    enum Step {
        case frame(TouchFrame)
        /// The system reported a physical click.
        case click
    }

    private(set) var steps: [Step] = []
    private(set) var time: Double = 0

    mutating func hold(_ touches: [Touch], for duration: Double) {
        let count = max(1, Int(duration * 100))
        for _ in 0..<count {
            time += 0.01
            steps.append(.frame(TouchFrame(timestamp: time, touches: touches)))
        }
    }

    mutating func click() { steps.append(.click) }

    mutating func lift() {
        time += 0.01
        steps.append(.frame(TouchFrame(timestamp: time, touches: [])))
    }

    mutating func idle(_ duration: Double) { time += duration }

    static func finger(_ id: Int, x: Double = 0.5, y: Double = 0.5, pressure: Double = 10) -> Touch {
        Touch(id: id, phase: .touching, position: Point(x: x, y: y), pressure: pressure)
    }

    static func fingers(_ count: Int, x: Double = 0.5, y: Double = 0.5, pressure: Double = 10) -> [Touch] {
        (0..<count).map { finger($0, x: x + Double($0) * 0.01, y: y, pressure: pressure) }
    }
}

func recognize(_ steps: [FrameBuilder.Step], settings: GestureSettings = GestureSettings()) -> [Trigger] {
    var recognizer = GestureRecognizer(settings: settings)
    return steps.flatMap { step -> [GestureEvent] in
        switch step {
        case let .frame(frame): return recognizer.process(frame)
        case .click:
            recognizer.registerPhysicalClick()
            return []
        }
    }.map(\.trigger)
}
