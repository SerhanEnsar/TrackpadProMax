import Foundation

/// Logic for the output-device bars opened by a hard press on the volume bar.
/// Sideways travel steps the highlight from bar to bar, vertical travel
/// changes the highlighted device's volume, a hard press switches to it and
/// a tap goes back. Multi-finger touches are ignored.
public struct DevicePicker: Sendable {
    public enum Event: Sendable, Equatable {
        case highlight(Int)
        case adjust(Int, Double)
        case activate(Int)
        case dismiss
    }

    public let itemCount: Int
    public private(set) var highlighted: Int

    /// Sideways travel (normalized) per highlight step.
    public var stepDistance = 0.12
    public var gain = 1.4
    public var deepPressThreshold: Double
    public var maxTapDuration: TimeInterval = 0.25
    public var maxTapMovement = 0.03

    private var trackedID: Int?
    private var last = Point(x: 0, y: 0)
    private var start = Point(x: 0, y: 0)
    private var startTime: TimeInterval = 0
    private var movement = 0.0
    private var sideways = 0.0
    private var pressed = false
    private var multiFinger = false

    public init(itemCount: Int, highlighted: Int, deepPressThreshold: Double = 750) {
        precondition(itemCount > 0)
        self.itemCount = itemCount
        self.highlighted = min(max(0, highlighted), itemCount - 1)
        self.deepPressThreshold = deepPressThreshold
    }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        if multiFinger {
            if active.isEmpty { multiFinger = false }
            return []
        }
        if active.count > 1 {
            multiFinger = true
            trackedID = nil
            return []
        }
        guard let touch = active.first else { return lift(at: frame.timestamp) }
        if touch.id != trackedID {
            trackedID = touch.id
            start = touch.position
            last = touch.position
            startTime = frame.timestamp
            movement = 0
            sideways = 0
            pressed = false
            return []
        }
        movement = max(movement, start.distance(to: touch.position))
        var events: [Event] = []
        if !pressed, touch.pressure >= deepPressThreshold, movement <= 0.06 {
            pressed = true
            events.append(.activate(highlighted))
        }

        let dx = touch.position.x - last.x, dy = touch.position.y - last.y
        last = touch.position
        // Whichever axis dominates this frame wins, so diagonal drift does not do both.
        if abs(dx) > abs(dy) {
            sideways += dx
            while abs(sideways) >= stepDistance {
                let direction = sideways > 0 ? 1 : -1
                sideways -= Double(direction) * stepDistance
                let next = min(max(0, highlighted + direction), itemCount - 1)
                if next != highlighted {
                    highlighted = next
                    events.append(.highlight(next))
                }
            }
        } else if dy != 0 {
            events.append(.adjust(highlighted, dy * gain))
        }
        return events
    }

    private mutating func lift(at time: TimeInterval) -> [Event] {
        guard trackedID != nil else { return [] }
        trackedID = nil
        if !pressed, time - startTime <= maxTapDuration, movement <= maxTapMovement {
            return [.dismiss]
        }
        return []
    }
}
