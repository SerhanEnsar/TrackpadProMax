import Foundation

/// How hard a press was, relative to the user's calibrated thresholds.
public enum PressTier: Int, Sendable, Codable, CaseIterable, Comparable {
    case light = 1
    case medium = 2
    case hard = 3

    public static func < (lhs: PressTier, rhs: PressTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .light: "Light press"
        case .medium: "Medium press"
        case .hard: "Hard press"
        }
    }
}

/// Region of the trackpad surface where a gesture happened.
public enum Zone: String, Sendable, Codable, CaseIterable {
    case anywhere
    case topLeft, topRight, bottomLeft, bottomRight
    case topEdge, bottomEdge, leftEdge, rightEdge
    case center

    public var displayName: String {
        switch self {
        case .anywhere: "Anywhere"
        case .topLeft: "Top-left corner"
        case .topRight: "Top-right corner"
        case .bottomLeft: "Bottom-left corner"
        case .bottomRight: "Bottom-right corner"
        case .topEdge: "Top edge"
        case .bottomEdge: "Bottom edge"
        case .leftEdge: "Left edge"
        case .rightEdge: "Right edge"
        case .center: "Center"
        }
    }

    /// Classifies a normalized point (origin bottom-left). `margin` is the
    /// fraction of width/height that counts as edge.
    public static func classify(_ point: Point, margin: Double) -> Zone {
        let left = point.x < margin, right = point.x > 1 - margin
        let bottom = point.y < margin, top = point.y > 1 - margin
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .leftEdge
        case (_, true, _, _): return .rightEdge
        case (_, _, true, _): return .topEdge
        case (_, _, _, true): return .bottomEdge
        default: return .center
        }
    }

    /// Whether a binding configured for `self` should fire for a gesture in `actual`.
    public func matches(_ actual: Zone) -> Bool { self == .anywhere || self == actual }
}

/// A recognizable trackpad input that can be bound to an action.
public enum Trigger: Hashable, Sendable, Codable {
    /// Quick touch without a physical click. `count` is 1 (single) or 2 (double).
    case tap(fingers: Int, count: Int, zone: Zone)
    /// Press that reached `tier` of force.
    case press(tier: PressTier, fingers: Int, zone: Zone)

    public var zone: Zone {
        switch self {
        case let .tap(_, _, zone), let .press(_, _, zone): zone
        }
    }

    public var fingers: Int {
        switch self {
        case let .tap(fingers, _, _), let .press(_, fingers, _): fingers
        }
    }

    /// True if a binding with trigger `self` should fire for the recognized `event`.
    public func matches(_ event: Trigger) -> Bool {
        switch (self, event) {
        case let (.tap(f1, c1, z1), .tap(f2, c2, z2)):
            f1 == f2 && c1 == c2 && z1.matches(z2)
        case let (.press(t1, f1, z1), .press(t2, f2, z2)):
            t1 == t2 && f1 == f2 && z1.matches(z2)
        default:
            false
        }
    }

    public var displayName: String {
        let hand = fingers == 1 ? "1 finger" : "\(fingers) fingers"
        let place = zone == .anywhere ? "" : " · \(zone.displayName)"
        switch self {
        case let .tap(_, count, _):
            return "\(count == 2 ? "Double tap" : "Tap") with \(hand)\(place)"
        case let .press(tier, _, _):
            return "\(tier.displayName) with \(hand)\(place)"
        }
    }
}
