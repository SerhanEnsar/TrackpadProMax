import Foundation

/// The window-tiling tool as a pure state machine over touch frames.
///
/// 1. **Count**: the trackpad is a 2×2 grid (Back, 2, 3, 4); press a quadrant.
/// 2. **Adjust**: the trackpad maps onto the screen; press near a divider and
///    drag it. A two-finger tap confirms.
/// 3. **Assign**: the left strip lists open apps (slide to highlight); press
///    one, drag it over a pane, let go to drop. Done when every pane is filled.
public struct TilingFlow: Sendable {
    public enum Phase: Sendable, Equatable {
        case chooseCount
        case adjust
        case assign
    }

    public enum Event: Sendable, Equatable {
        /// 0 = top-left (Back), 1 = top-right (2), 2 = bottom-left (3), 3 = bottom-right (4).
        case highlightQuadrant(Int?)
        case back
        case chooseCount(Int)
        case hoverDivider(TilingLayout.Divider?)
        case grabDivider(TilingLayout.Divider)
        case moveDivider(TilingLayout.Divider, Double)
        case releaseDivider
        case confirmLayout
        case highlightApp(Int)
        case pickUpApp(Int)
        /// Dragged icon position in layout coordinates (y down).
        case dragMoved(Point)
        case hoverPane(Int?)
        case dropApp(app: Int, pane: Int)
        case cancelDrag
        /// pane → app
        case complete([Int: Int])
    }

    public private(set) var phase = Phase.chooseCount
    public private(set) var layout = TilingLayout(count: 2)
    public private(set) var highlightedApp = 0
    public private(set) var assignments: [Int: Int] = [:]
    public let appCount: Int

    public var pressThreshold: Double
    public var releaseRatio = 0.7
    /// Width of the app strip on the left of the trackpad in the assign phase.
    public static let stripWidth = 0.22
    public var stripStep = 0.08
    public var maxTapDuration: TimeInterval = 0.3
    public var maxTapMovement = 0.04

    // Touch session state
    private var sessionStart: TimeInterval?
    private var maxFingers = 0
    private var startCentroid = Point(x: 0, y: 0)
    private var sessionMovement = 0.0
    private var pressed = false
    /// After a phase change, ignore touches until all fingers lift.
    private var waitingForLift = false

    private var quadrant: Int?
    private var hoveredDivider: TilingLayout.Divider?
    private var grabbed: TilingLayout.Divider?
    private var lastStripY: Double?
    private var stripAccumulator = 0.0
    private var draggingApp: Int?
    private var hoveredPane: Int?

    public init(appCount: Int, pressThreshold: Double = 120) {
        self.appCount = appCount
        self.pressThreshold = pressThreshold
    }

    /// Panes to fill before tiling: all of them, or fewer if fewer apps are open.
    public var panesToFill: Int { min(layout.count, appCount) }

    /// Trackpad (y up) → layout (y down) over the whole pad.
    static func layoutPoint(_ p: Point) -> Point { Point(x: p.x, y: 1 - p.y) }

    /// Trackpad → layout over the drop area right of the app strip.
    static func dropPoint(_ p: Point) -> Point {
        Point(x: (p.x - stripWidth) / (1 - stripWidth), y: 1 - p.y)
    }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        if active.isEmpty { return endSession(at: frame.timestamp) }
        if waitingForLift { return [] }

        if sessionStart == nil {
            sessionStart = frame.timestamp
            maxFingers = 0
            startCentroid = centroid(active)
            sessionMovement = 0
        }
        maxFingers = max(maxFingers, active.count)
        sessionMovement = max(sessionMovement, startCentroid.distance(to: centroid(active)))
        // Multi-finger contact is reserved for the two-finger tap.
        guard maxFingers == 1, let touch = active.first else {
            return releaseEverything()
        }

        let force = touch.pressure
        let wasPressed = pressed
        if !pressed, force >= pressThreshold { pressed = true }
        if pressed, force < pressThreshold * releaseRatio { pressed = false }
        let pressBegan = pressed && !wasPressed
        let pressEnded = !pressed && wasPressed

        switch phase {
        case .chooseCount: return chooseCount(touch.position, pressBegan: pressBegan)
        case .adjust: return adjust(touch.position, pressBegan: pressBegan, pressEnded: pressEnded)
        case .assign: return assign(touch.position, pressBegan: pressBegan, pressEnded: pressEnded)
        }
    }

    // MARK: Phases

    private mutating func chooseCount(_ p: Point, pressBegan: Bool) -> [Event] {
        var events: [Event] = []
        let q = (p.y > 0.5 ? 0 : 2) + (p.x > 0.5 ? 1 : 0)
        if q != quadrant {
            quadrant = q
            events.append(.highlightQuadrant(q))
        }
        guard pressBegan else { return events }
        if q == 0 {
            events.append(.back)
        } else {
            let count = [0, 2, 3, 4][q]
            layout = TilingLayout(count: count)
            phase = .adjust
            waitingForLift = true
            quadrant = nil
            events.append(.chooseCount(count))
        }
        return events
    }

    private mutating func adjust(_ p: Point, pressBegan: Bool, pressEnded: Bool) -> [Event] {
        let point = Self.layoutPoint(p)
        var events: [Event] = []
        if let divider = grabbed {
            if pressEnded {
                grabbed = nil
                events.append(.releaseDivider)
            } else {
                layout.move(divider, to: divider == .vertical ? point.x : point.y)
                events.append(.moveDivider(divider, divider == .vertical ? layout.splitX : layout.splitY))
            }
            return events
        }
        let near = layout.divider(near: point)
        if near != hoveredDivider {
            hoveredDivider = near
            events.append(.hoverDivider(near))
        }
        if pressBegan, let near {
            grabbed = near
            events.append(.grabDivider(near))
        }
        return events
    }

    private mutating func assign(_ p: Point, pressBegan: Bool, pressEnded: Bool) -> [Event] {
        var events: [Event] = []
        if let app = draggingApp {
            let point = Self.dropPoint(p)
            events.append(.dragMoved(point))
            let pane = layout.pane(at: point)
            if pane != hoveredPane {
                hoveredPane = pane
                events.append(.hoverPane(pane))
            }
            if pressEnded { events += drop(app) }
            return events
        }
        guard p.x < Self.stripWidth else {
            lastStripY = nil
            return events
        }
        // Scroll the strip: finger up = earlier apps (like a list under the finger).
        if let last = lastStripY {
            stripAccumulator += p.y - last
            while abs(stripAccumulator) >= stripStep {
                let direction = stripAccumulator > 0 ? -1 : 1
                stripAccumulator += Double(direction) * stripStep
                let next = min(max(0, highlightedApp + direction), max(0, appCount - 1))
                if next != highlightedApp {
                    highlightedApp = next
                    events.append(.highlightApp(next))
                }
            }
        }
        lastStripY = p.y
        if pressBegan, appCount > 0 {
            draggingApp = highlightedApp
            hoveredPane = nil
            events.append(.pickUpApp(highlightedApp))
        }
        return events
    }

    private mutating func drop(_ app: Int) -> [Event] {
        draggingApp = nil
        defer { hoveredPane = nil }
        guard let pane = hoveredPane else { return [.cancelDrag] }
        // One pane per app: moving an app frees its old pane.
        assignments = assignments.filter { $0.value != app }
        assignments[pane] = app
        var events: [Event] = [.dropApp(app: app, pane: pane)]
        if assignments.count >= panesToFill {
            events.append(.complete(assignments))
        }
        return events
    }

    // MARK: Sessions

    private mutating func releaseEverything() -> [Event] {
        var events: [Event] = []
        if grabbed != nil {
            grabbed = nil
            events.append(.releaseDivider)
        }
        if draggingApp != nil {
            draggingApp = nil
            hoveredPane = nil
            events.append(.cancelDrag)
        }
        pressed = false
        return events
    }

    private mutating func endSession(at time: TimeInterval) -> [Event] {
        defer {
            sessionStart = nil
            waitingForLift = false
            lastStripY = nil
            stripAccumulator = 0
        }
        guard let start = sessionStart, !waitingForLift else { return [] }
        var events: [Event] = []
        // Lifting while dragging drops; lifting while holding a divider releases it.
        if let app = draggingApp, phase == .assign {
            events += drop(app)
        } else {
            events += releaseEverything()
        }
        pressed = false
        let isTwoFingerTap = maxFingers == 2 && time - start <= maxTapDuration && sessionMovement <= maxTapMovement
        if isTwoFingerTap, phase == .adjust {
            phase = .assign
            hoveredDivider = nil
            events.append(.confirmLayout)
        }
        return events
    }

    private func centroid(_ touches: [Touch]) -> Point {
        let n = Double(touches.count)
        return Point(x: touches.map(\.position.x).reduce(0, +) / n, y: touches.map(\.position.y).reduce(0, +) / n)
    }
}
