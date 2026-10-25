import Foundation

/// Logic behind the mode wheel. A virtual knob inside the wheel follows the
/// finger's relative movement (not the cursor); the sector it points to is
/// highlighted. A tap confirms the highlighted item, or cancels when the
/// knob rests in the center.
public struct RadialSelector: Sendable {
    public enum Event: Sendable, Equatable {
        case highlight(Int?)
        /// A tap: `nil` means "cancel" (knob in the center).
        case confirm(Int?)
    }

    public let itemCount: Int
    /// Knob position, unit circle, y up. Read it to draw the knob.
    public private(set) var knob = Point(x: 0, y: 0)
    public private(set) var highlighted: Int?

    /// Finger travel (normalized pad units) that moves the knob from center to rim.
    public var travel = 0.22
    /// Knob distance below which nothing is highlighted.
    public var deadZone = 0.4
    public var maxTapDuration: TimeInterval = 0.25
    public var maxTapMovement = 0.03

    private var trackedID: Int?
    private var lastPosition: Point?
    private var touchStart: TimeInterval = 0
    private var touchMovement = 0.0
    private var startPosition = Point(x: 0, y: 0)

    public init(itemCount: Int, highlighted: Int? = nil) {
        precondition(itemCount > 0)
        self.itemCount = itemCount
        if let highlighted {
            self.highlighted = highlighted
            let angle = Self.angle(of: highlighted, count: itemCount)
            knob = Point(x: sin(angle), y: cos(angle))
        }
    }

    /// Angle of item `index` measured clockwise from 12 o'clock.
    public static func angle(of index: Int, count: Int) -> Double {
        Double(index) / Double(count) * 2 * .pi
    }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        // Follow one finger; extra fingers are ignored.
        guard let touch = active.first(where: { $0.id == trackedID }) ?? active.first else {
            return lift(at: frame.timestamp)
        }
        if touch.id != trackedID {
            // New finger (or a switch to another one): start a fresh slide.
            trackedID = touch.id
            lastPosition = touch.position
            startPosition = touch.position
            touchStart = frame.timestamp
            touchMovement = 0
            return []
        }
        guard let last = lastPosition else { return [] }
        lastPosition = touch.position
        touchMovement = max(touchMovement, startPosition.distance(to: touch.position))

        // Trackpad is ~1.6x wider than tall; scale x so motion feels round.
        var x = knob.x + (touch.position.x - last.x) * 1.6 / travel
        var y = knob.y + (touch.position.y - last.y) / travel
        let length = (x * x + y * y).squareRoot()
        if length > 1 { x /= length; y /= length }
        knob = Point(x: x, y: y)
        return updateHighlight()
    }

    private mutating func lift(at time: TimeInterval) -> [Event] {
        guard trackedID != nil else { return [] }
        trackedID = nil
        lastPosition = nil
        if time - touchStart <= maxTapDuration, touchMovement <= maxTapMovement {
            return [.confirm(highlighted)]
        }
        return []
    }

    private mutating func updateHighlight() -> [Event] {
        let length = (knob.x * knob.x + knob.y * knob.y).squareRoot()
        var index: Int?
        if length >= deadZone {
            var angle = atan2(knob.x, knob.y) // clockwise from up
            if angle < 0 { angle += 2 * .pi }
            let sector = 2 * .pi / Double(itemCount)
            index = Int((angle / sector).rounded()) % itemCount
        }
        guard index != highlighted else { return [] }
        highlighted = index
        return [.highlight(index)]
    }
}
