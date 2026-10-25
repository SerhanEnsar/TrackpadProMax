import Foundation

/// The timer tool's dial: circling a finger around the middle of the trackpad
/// turns the minutes up (clockwise) or down. A firm press away from the middle
/// starts (or cancels a running timer); a tap in the middle goes back.
public struct TimerKnob: Sendable {
    public enum Event: Sendable, Equatable {
        case minutes(Int)
        case start(Int)
        case back
    }

    public private(set) var minutes: Int
    public var degreesPerMinute = 30.0
    public var range = 0...120
    /// Touches closer than this to the center do not turn the dial (angle is noisy there).
    public var deadRadius = 0.12
    /// Taps within this radius of the center mean Back.
    public var centerRadius = 0.15
    public var maxTapDuration: TimeInterval = 0.25
    public var maxTapMovement = 0.03
    /// Force that starts the timer; usually the hard-press threshold.
    public var startThreshold: Double
    /// A press only counts if the finger stayed put (not mid-circle).
    public var maxPressMovement = 0.06
    private var pressed = false

    private var accumulated = 0.0
    private var baseMinutes: Int
    private var lastAngle: Double?
    private var trackedID: Int?
    private var start = Point(x: 0, y: 0)
    private var startTime: TimeInterval = 0
    private var movement = 0.0
    private var multiFinger = false

    public init(minutes: Int = 25, startThreshold: Double = 750) {
        self.minutes = minutes
        baseMinutes = minutes
        self.startThreshold = startThreshold
    }

    /// Offset from the pad center, with x scaled so circles feel round on a wide pad.
    static func offset(_ p: Point) -> Point { Point(x: (p.x - 0.5) * 1.6, y: p.y - 0.5) }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        if multiFinger {
            if active.isEmpty { multiFinger = false }
            return []
        }
        if active.count > 1 {
            multiFinger = true
            trackedID = nil
            lastAngle = nil
            return []
        }
        guard let touch = active.first else { return lift(at: frame.timestamp) }
        if touch.id != trackedID {
            trackedID = touch.id
            start = touch.position
            startTime = frame.timestamp
            movement = 0
            lastAngle = nil
            pressed = false
        }
        movement = max(movement, start.distance(to: touch.position))

        let startOffset = Self.offset(start)
        let inCenter = (startOffset.x * startOffset.x + startOffset.y * startOffset.y).squareRoot() < centerRadius
        if !pressed, !inCenter, touch.pressure >= startThreshold, movement <= maxPressMovement {
            pressed = true
            return [.start(minutes)]
        }

        let o = Self.offset(touch.position)
        guard (o.x * o.x + o.y * o.y).squareRoot() >= deadRadius else {
            lastAngle = nil
            return []
        }
        let angle = atan2(o.x, o.y) // clockwise from 12 o'clock
        defer { lastAngle = angle }
        guard let last = lastAngle else { return [] }
        var delta = angle - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        accumulated += delta * 180 / .pi

        // Clamp the accumulator only past a limit, so turning back from a
        // limit responds at once without eating partial turns inside the range.
        let low = Double(range.lowerBound - baseMinutes) * degreesPerMinute
        let high = Double(range.upperBound - baseMinutes) * degreesPerMinute
        accumulated = min(high, max(low, accumulated))
        let target = baseMinutes + Int((accumulated / degreesPerMinute).rounded(.towardZero))
        guard target != minutes else { return [] }
        minutes = target
        return [.minutes(target)]
    }

    private mutating func lift(at time: TimeInterval) -> [Event] {
        guard trackedID != nil else { return [] }
        trackedID = nil
        lastAngle = nil
        guard !pressed, time - startTime <= maxTapDuration, movement <= maxTapMovement else { return [] }
        let o = Self.offset(start)
        return (o.x * o.x + o.y * o.y).squareRoot() < centerRadius ? [.back] : []
    }
}
