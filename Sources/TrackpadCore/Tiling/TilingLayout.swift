import Foundation

/// Normalized rectangle, origin top-left, y down (screen-like).
public struct Rect: Sendable, Equatable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height
    }
}

/// How the screen is split for window tiling. Panes always cover the whole
/// screen with no gaps; moving a divider resizes the panes on both sides.
///
/// - 2: left | right
/// - 3: big left | right column split top/bottom
/// - 4: 2×2 grid
public struct TilingLayout: Sendable, Equatable {
    public enum Divider: Sendable, Equatable {
        /// Splits left from right at `splitX`.
        case vertical
        /// Splits top from bottom at `splitY` (right column only for 3 panes).
        case horizontal
    }

    public let count: Int
    public private(set) var splitX = 0.5
    public private(set) var splitY = 0.5

    public static let minSplit = 0.2
    public static let maxSplit = 0.8

    public init(count: Int) {
        precondition((2...4).contains(count))
        self.count = count
    }

    public var dividers: [Divider] { count == 2 ? [.vertical] : [.vertical, .horizontal] }

    public var panes: [Rect] {
        let x = splitX, y = splitY
        switch count {
        case 2:
            return [Rect(x: 0, y: 0, width: x, height: 1), Rect(x: x, y: 0, width: 1 - x, height: 1)]
        case 3:
            return [
                Rect(x: 0, y: 0, width: x, height: 1),
                Rect(x: x, y: 0, width: 1 - x, height: y),
                Rect(x: x, y: y, width: 1 - x, height: 1 - y),
            ]
        default:
            return [
                Rect(x: 0, y: 0, width: x, height: y), Rect(x: x, y: 0, width: 1 - x, height: y),
                Rect(x: 0, y: y, width: x, height: 1 - y), Rect(x: x, y: y, width: 1 - x, height: 1 - y),
            ]
        }
    }

    /// Line segment of a divider, for drawing and hit testing.
    public func segment(_ divider: Divider) -> (Point, Point) {
        switch divider {
        case .vertical: (Point(x: splitX, y: 0), Point(x: splitX, y: 1))
        case .horizontal: (Point(x: count == 3 ? splitX : 0, y: splitY), Point(x: 1, y: splitY))
        }
    }

    public mutating func move(_ divider: Divider, to value: Double) {
        let clamped = min(Self.maxSplit, max(Self.minSplit, value))
        switch divider {
        case .vertical: splitX = clamped
        case .horizontal: splitY = clamped
        }
    }

    /// Divider within `tolerance` of `point`, nearest first.
    public func divider(near point: Point, tolerance: Double = 0.07) -> Divider? {
        dividers
            .map { divider -> (Divider, Double) in
                let (a, b) = segment(divider)
                let distance: Double
                switch divider {
                case .vertical:
                    distance = abs(point.x - a.x)
                case .horizontal:
                    let outside = point.x < a.x ? a.x - point.x : (point.x > b.x ? point.x - b.x : 0)
                    distance = max(abs(point.y - a.y), outside)
                }
                return (divider, distance)
            }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    public func pane(at point: Point) -> Int? {
        panes.firstIndex { $0.contains(point) }
    }
}
