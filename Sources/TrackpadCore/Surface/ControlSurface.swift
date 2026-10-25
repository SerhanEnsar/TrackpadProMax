import Foundation

/// What a bar on one edge of the control surface does.
public enum SurfaceControl: String, Sendable, Codable, CaseIterable {
    case none
    case volume
    case brightness
    case keyboardBacklight
    /// Swipe for previous/next track, tap to play/pause.
    case media
    /// Scrub through the playing track.
    case seek

    public var displayName: String {
        switch self {
        case .none: "Nothing"
        case .volume: "Volume"
        case .brightness: "Display brightness"
        case .keyboardBacklight: "Keyboard backlight"
        case .media: "Tracks (swipe / tap)"
        case .seek: "Track position"
        }
    }

    public var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .keyboardBacklight: "light.max"
        case .media: "playpause.fill"
        case .seek: "timeline.selection"
        }
    }

    /// Continuous controls have a 0...1 value; `media` is discrete.
    public var isContinuous: Bool { self != .none && self != .media }

    /// Controls about the playing track; their surface shows Now Playing.
    public var isMusic: Bool { self == .media || self == .seek }
}

public enum SurfaceEdge: String, Sendable, Codable, CaseIterable {
    case left, right, top, bottom

    /// Bars on the left/right run vertically.
    public var isVertical: Bool { self == .left || self == .right }

    public var displayName: String { rawValue.capitalized }
}

/// Which control sits on which edge.
public struct ControlSurfaceLayout: Sendable, Codable, Hashable {
    public var left: SurfaceControl = .brightness
    public var right: SurfaceControl = .volume
    public var top: SurfaceControl = .media
    public var bottom: SurfaceControl = .keyboardBacklight

    public init() {}

    public init(left: SurfaceControl, right: SurfaceControl, top: SurfaceControl, bottom: SurfaceControl) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    /// Music-focused layout used by the default Media mode.
    public static let music = ControlSurfaceLayout(left: .none, right: .volume, top: .media, bottom: .seek)

    /// True if any edge controls playback, so the surface shows Now Playing
    /// and a tap in the middle plays/pauses.
    public var isMusic: Bool { SurfaceEdge.allCases.contains { self[$0].isMusic } }

    public subscript(edge: SurfaceEdge) -> SurfaceControl {
        get {
            switch edge {
            case .left: left
            case .right: right
            case .top: top
            case .bottom: bottom
            }
        }
        set {
            switch edge {
            case .left: left = newValue
            case .right: right = newValue
            case .top: top = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ControlSurfaceLayout()
        left = (try? c.decodeIfPresent(SurfaceControl.self, forKey: .left)) ?? d.left
        right = (try? c.decodeIfPresent(SurfaceControl.self, forKey: .right)) ?? d.right
        top = (try? c.decodeIfPresent(SurfaceControl.self, forKey: .top)) ?? d.top
        bottom = (try? c.decodeIfPresent(SurfaceControl.self, forKey: .bottom)) ?? d.bottom
    }
}

/// Turns touches into edge-bar interactions for the control surface mode.
/// A touch belongs to the edge band where it starts; sliding along the band
/// adjusts that bar, a quick touch taps it, a sideways flick swipes it.
public struct ControlSurfaceTracker: Sendable {
    public enum Event: Sendable, Equatable {
        case began(SurfaceEdge)
        /// Relative change; a slide across the whole pad is 1.0.
        case adjust(SurfaceEdge, Double)
        case tap(SurfaceEdge)
        /// +1 = right/up, -1 = left/down.
        case swipe(SurfaceEdge, Int)
        case ended(SurfaceEdge)
        /// Quick touch in the middle, away from every edge band.
        case centerTap
    }

    /// Size of each edge band, as a fraction of width/height.
    public var band = 0.3
    /// Slide needed for a swipe.
    public var swipeDistance = 0.15
    public var maxTapDuration: TimeInterval = 0.25
    public var maxTapMovement = 0.03
    /// Multiplier on finger travel; >1 lets a shorter slide cover the range.
    public var gain = 1.4

    private var trackedID: Int?
    private var edge: SurfaceEdge?
    private var last = Point(x: 0, y: 0)
    private var start = Point(x: 0, y: 0)
    private var startTime: TimeInterval = 0
    private var movement = 0.0
    private var swipeAccumulator = 0.0
    private var swiped = false

    public init() {}

    /// Edge band containing `point`, or nil for the middle. Corners go to
    /// the nearer edge.
    public func edge(at point: Point) -> SurfaceEdge? {
        let distances: [(SurfaceEdge, Double)] = [
            (.left, point.x), (.right, 1 - point.x), (.bottom, point.y), (.top, 1 - point.y),
        ]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < band else { return nil }
        return nearest.0
    }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        guard let touch = active.first(where: { $0.id == trackedID }) ?? (trackedID == nil ? active.first : nil) else {
            return end(at: frame.timestamp)
        }
        if trackedID == nil {
            trackedID = touch.id
            edge = edge(at: touch.position)
            start = touch.position
            last = touch.position
            startTime = frame.timestamp
            movement = 0
            swipeAccumulator = 0
            swiped = false
            return edge.map { [.began($0)] } ?? []
        }
        movement = max(movement, start.distance(to: touch.position))
        guard let edge else { return [] }
        let delta = edge.isVertical ? touch.position.y - last.y : touch.position.x - last.x
        last = touch.position
        guard delta != 0 else { return [] }

        swipeAccumulator += delta
        var events: [Event] = [.adjust(edge, delta * gain)]
        if !swiped, abs(swipeAccumulator) >= swipeDistance {
            swiped = true
            events.append(.swipe(edge, swipeAccumulator > 0 ? 1 : -1))
        }
        return events
    }

    private mutating func end(at time: TimeInterval) -> [Event] {
        guard trackedID != nil else { return [] }
        trackedID = nil
        defer { edge = nil }
        let isTap = time - startTime <= maxTapDuration && movement <= maxTapMovement
        guard let edge else { return isTap ? [.centerTap] : [] }
        if isTap {
            return [.tap(edge), .ended(edge)]
        }
        return [.ended(edge)]
    }
}
