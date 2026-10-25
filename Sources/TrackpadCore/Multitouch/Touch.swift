import Foundation

/// Lifecycle phase of a single finger contact as reported by the trackpad.
public enum TouchPhase: Int, Sendable, Codable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7

    /// True while the finger is physically in contact with the surface.
    public var isDown: Bool { self == .makeTouch || self == .touching }
}

public struct Point: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// One finger in one frame.
public struct Touch: Sendable, Equatable {
    public var id: Int
    public var phase: TouchPhase
    /// Normalized position, 0...1 on both axes, origin at bottom-left.
    public var position: Point
    public var velocity: Point
    /// Raw force reading. Roughly 0 when resting, grows with applied force.
    public var pressure: Double
    /// Contact size (total capacitance).
    public var size: Double
    public var angle: Double
    public var majorAxis: Double
    public var minorAxis: Double

    public init(
        id: Int, phase: TouchPhase, position: Point, velocity: Point = Point(x: 0, y: 0),
        pressure: Double = 0, size: Double = 0, angle: Double = 0, majorAxis: Double = 0, minorAxis: Double = 0
    ) {
        self.id = id
        self.phase = phase
        self.position = position
        self.velocity = velocity
        self.pressure = pressure
        self.size = size
        self.angle = angle
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
    }
}

/// All contacts reported by the trackpad at one instant.
public struct TouchFrame: Sendable, Equatable {
    public var timestamp: TimeInterval
    public var touches: [Touch]

    public init(timestamp: TimeInterval, touches: [Touch]) {
        self.timestamp = timestamp
        self.touches = touches
    }

    public var activeTouches: [Touch] { touches.filter { $0.phase.isDown } }
}
