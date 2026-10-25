import Foundation

/// Tunable thresholds for gesture recognition.
public struct GestureSettings: Sendable, Codable, Equatable {
    /// Force needed to reach each tier. Raw MultitouchSupport units (roughly grams).
    public var lightThreshold: Double = 60
    public var mediumThreshold: Double = 220
    public var hardThreshold: Double = 420
    /// A tier is left once force drops below `threshold * releaseRatio`.
    public var releaseRatio: Double = 0.7
    /// Taps must be shorter than this.
    public var maxTapDuration: TimeInterval = 0.22
    /// Max finger travel during a tap or press, in normalized units.
    public var maxTapMovement: Double = 0.03
    public var maxPressMovement: Double = 0.06
    /// Second tap must start within this time after the first ends.
    public var doubleTapInterval: TimeInterval = 0.3
    /// Fraction of width/height treated as edge/corner zone.
    public var zoneMargin: Double = 0.18

    public init() {}

    public func threshold(for tier: PressTier) -> Double {
        switch tier {
        case .light: lightThreshold
        case .medium: mediumThreshold
        case .hard: hardThreshold
        }
    }

    public func tier(forForce force: Double) -> PressTier? {
        PressTier.allCases.last { force >= threshold(for: $0) }
    }
}

/// A gesture recognized at a point in time.
public struct GestureEvent: Sendable, Equatable {
    public var trigger: Trigger
    public var timestamp: TimeInterval
    public var location: Point
}

/// Turns a stream of `TouchFrame`s into taps and pressure presses.
///
/// Pure value type with no timers or system calls, so it can be unit-tested with
/// synthetic frames. A "session" lasts from the first finger down until all
/// fingers lift.
public struct GestureRecognizer: Sendable {
    public var settings: GestureSettings

    private struct Session {
        var start: TimeInterval
        var startPositions: [Int: Point] = [:]
        var startCentroid: Point
        var maxFingers = 0
        var maxMovement = 0.0
        var peakForce = 0.0
        var pressFired = false
        /// Highest tier reached since the last re-arm, waiting to be emitted at peak.
        var pendingTier: PressTier?
        var pendingFingers = 0
        var pendingLocation = Point(x: 0, y: 0)
        var armed = true
    }

    private var session: Session?
    private var lastTap: (fingers: Int, zone: Zone, end: TimeInterval)?

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// Current max force across active fingers in the last processed frame.
    public private(set) var currentForce = 0.0

    public mutating func process(_ frame: TouchFrame) -> [GestureEvent] {
        let active = frame.activeTouches
        var events: [GestureEvent] = []

        if active.isEmpty {
            currentForce = 0
            if let ended = session {
                events += finish(ended, at: frame.timestamp)
                session = nil
            }
            return events
        }

        if session == nil {
            session = Session(start: frame.timestamp, startCentroid: centroid(of: active))
        }
        guard var current = session else { return events }

        current.maxFingers = max(current.maxFingers, active.count)
        for touch in active {
            if let origin = current.startPositions[touch.id] {
                current.maxMovement = max(current.maxMovement, origin.distance(to: touch.position))
            } else {
                current.startPositions[touch.id] = touch.position
            }
        }

        let force = active.map(\.pressure).max() ?? 0
        currentForce = force
        current.peakForce = max(current.peakForce, force)
        events += trackPress(&current, force: force, fingers: active.count, location: centroid(of: active), at: frame.timestamp)

        session = current
        return events
    }

    private mutating func trackPress(
        _ s: inout Session, force: Double, fingers: Int, location: Point, at time: TimeInterval
    ) -> [GestureEvent] {
        if !s.armed {
            if force < settings.lightThreshold * settings.releaseRatio { s.armed = true }
            return []
        }
        guard s.maxMovement <= settings.maxPressMovement else {
            s.pendingTier = nil
            return []
        }
        if let tier = settings.tier(forForce: force), tier > (s.pendingTier ?? .light) || s.pendingTier == nil {
            s.pendingTier = tier
            s.pendingFingers = fingers
            s.pendingLocation = location
        }
        guard let tier = s.pendingTier else { return [] }

        // Fire right away at the top tier; otherwise wait until force falls off
        // the tier, so a hard press does not also fire light and medium.
        let releasing = force < settings.threshold(for: tier) * settings.releaseRatio
        guard tier == .hard || releasing else { return [] }
        return [emitPress(&s, tier: tier, at: time)]
    }

    private func emitPress(_ s: inout Session, tier: PressTier, at time: TimeInterval) -> GestureEvent {
        s.pressFired = true
        s.pendingTier = nil
        s.armed = false
        let zone = Zone.classify(s.pendingLocation, margin: settings.zoneMargin)
        return GestureEvent(
            trigger: .press(tier: tier, fingers: s.pendingFingers, zone: zone),
            timestamp: time, location: s.pendingLocation
        )
    }

    private mutating func finish(_ s: Session, at time: TimeInterval) -> [GestureEvent] {
        var s = s
        if let tier = s.pendingTier, s.maxMovement <= settings.maxPressMovement {
            return [emitPress(&s, tier: tier, at: time)]
        }
        guard !s.pressFired,
              time - s.start <= settings.maxTapDuration,
              s.maxMovement <= settings.maxTapMovement,
              s.peakForce < settings.lightThreshold
        else {
            lastTap = nil
            return []
        }
        let zone = Zone.classify(s.startCentroid, margin: settings.zoneMargin)
        var count = 1
        if let previous = lastTap, previous.fingers == s.maxFingers, previous.zone == zone,
           s.start - previous.end <= settings.doubleTapInterval {
            count = 2
            lastTap = nil
        } else {
            lastTap = (s.maxFingers, zone, time)
        }
        return [GestureEvent(
            trigger: .tap(fingers: s.maxFingers, count: count, zone: zone),
            timestamp: time, location: s.startCentroid
        )]
    }

    private func centroid(of touches: [Touch]) -> Point {
        let n = Double(touches.count)
        return Point(
            x: touches.map(\.position.x).reduce(0, +) / n,
            y: touches.map(\.position.y).reduce(0, +) / n
        )
    }
}
