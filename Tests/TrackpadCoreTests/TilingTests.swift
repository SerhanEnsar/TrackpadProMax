import Foundation
import Testing
@testable import TrackpadCore

/// Builds frames for one finger with a force profile.
private struct Pad {
    var frames: [TouchFrame] = []
    var t = 0.0
    var id = 1

    mutating func hold(_ p: Point, force: Double = 20, steps: Int = 5) {
        for _ in 0..<steps {
            t += 0.01
            frames.append(TouchFrame(timestamp: t, touches: [Touch(id: id, phase: .touching, position: p, pressure: force)]))
        }
    }

    mutating func move(from a: Point, to b: Point, force: Double, steps: Int = 20) {
        for i in 0...steps {
            let k = Double(i) / Double(steps)
            hold(Point(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), force: force, steps: 1)
        }
    }

    /// Light press at `p`: rest, push past the click threshold, ease off, lift.
    mutating func press(_ p: Point) {
        hold(p, force: 20)
        hold(p, force: 200)
        hold(p, force: 20)
        lift()
    }

    mutating func twoFingerTap() {
        for _ in 0..<5 {
            t += 0.01
            frames.append(TouchFrame(timestamp: t, touches: [
                Touch(id: 10, phase: .touching, position: Point(x: 0.45, y: 0.5), pressure: 20),
                Touch(id: 11, phase: .touching, position: Point(x: 0.55, y: 0.5), pressure: 20),
            ]))
        }
        lift()
    }

    mutating func lift() {
        t += 0.05
        frames.append(TouchFrame(timestamp: t, touches: []))
        id += 1
    }
}

private func run(_ flow: inout TilingFlow, _ pad: Pad) -> [TilingFlow.Event] {
    pad.frames.flatMap { flow.process($0) }
}

@Suite struct TilingLayoutTests {
    @Test func panesCoverScreenWithoutGaps() {
        for count in 2...4 {
            var layout = TilingLayout(count: count)
            layout.move(.vertical, to: 0.37)
            if count > 2 { layout.move(.horizontal, to: 0.61) }
            let area = layout.panes.reduce(0) { $0 + $1.width * $1.height }
            #expect(abs(area - 1) < 1e-9, "count \(count)")
            #expect(layout.panes.count == count)
        }
    }

    @Test func threeIsBigLeftPlusStackedRight() {
        let panes = TilingLayout(count: 3).panes
        #expect(panes[0] == Rect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(panes[1].height == 0.5 && panes[2].y == 0.5)
    }

    @Test func dividersClampAndHitTest() {
        var layout = TilingLayout(count: 3)
        layout.move(.vertical, to: 0.05)
        #expect(layout.splitX == TilingLayout.minSplit)
        #expect(layout.divider(near: Point(x: 0.22, y: 0.9)) == .vertical)
        // The 3-pane horizontal divider only exists in the right column.
        #expect(layout.divider(near: Point(x: 0.1, y: 0.5)) == nil)
        #expect(layout.divider(near: Point(x: 0.7, y: 0.52)) == .horizontal)
    }
}

@Suite struct TilingFlowTests {
    @Test func pressTopLeftGoesBack() {
        var flow = TilingFlow(appCount: 3)
        var pad = Pad()
        pad.press(Point(x: 0.2, y: 0.8))
        let events = run(&flow, pad)
        #expect(events.contains(.back))
        #expect(flow.phase == .chooseCount)
    }

    @Test func pressQuadrantsPicksCount() {
        for (point, count) in [(Point(x: 0.8, y: 0.8), 2), (Point(x: 0.2, y: 0.2), 3), (Point(x: 0.8, y: 0.2), 4)] {
            var flow = TilingFlow(appCount: 4)
            var pad = Pad()
            pad.press(point)
            #expect(run(&flow, pad).contains(.chooseCount(count)))
            #expect(flow.phase == .adjust && flow.layout.count == count)
        }
    }

    @Test func hoverWithoutPressOnlyHighlights() {
        var flow = TilingFlow(appCount: 3)
        var pad = Pad()
        pad.move(from: Point(x: 0.2, y: 0.8), to: Point(x: 0.8, y: 0.2), force: 20)
        pad.lift()
        let events = run(&flow, pad)
        #expect(events.allSatisfy { if case .highlightQuadrant = $0 { true } else { false } })
        #expect(flow.phase == .chooseCount)
    }

    fileprivate func adjusting(count: Int, apps: Int = 4) -> (TilingFlow, Pad) {
        var flow = TilingFlow(appCount: apps)
        var pad = Pad()
        let point = [2: Point(x: 0.8, y: 0.8), 3: Point(x: 0.2, y: 0.2), 4: Point(x: 0.8, y: 0.2)][count]!
        pad.press(point)
        _ = run(&flow, pad)
        return (flow, Pad(t: pad.t, id: pad.id))
    }

    @Test func dragDividerResizesPanes() {
        var (flow, pad) = adjusting(count: 2)
        pad.hold(Point(x: 0.5, y: 0.5), force: 20)
        pad.hold(Point(x: 0.5, y: 0.5), force: 200, steps: 2)
        pad.move(from: Point(x: 0.5, y: 0.5), to: Point(x: 0.7, y: 0.5), force: 200)
        pad.hold(Point(x: 0.7, y: 0.5), force: 20)
        pad.lift()
        let events = run(&flow, pad)
        #expect(events.contains(.grabDivider(.vertical)))
        #expect(events.contains(.releaseDivider))
        #expect(abs(flow.layout.splitX - 0.7) < 0.001)
    }

    @Test func pressAwayFromDividerDoesNothing() {
        var (flow, pad) = adjusting(count: 2)
        pad.press(Point(x: 0.1, y: 0.5))
        let events = run(&flow, pad)
        #expect(!events.contains { if case .grabDivider = $0 { true } else { false } })
    }

    @Test func twoFingerTapConfirms() {
        var (flow, pad) = adjusting(count: 3)
        pad.twoFingerTap()
        #expect(run(&flow, pad).contains(.confirmLayout))
        #expect(flow.phase == .assign)
    }

    @Test func staggeredTwoFingerTapConfirms() {
        var (flow, pad) = adjusting(count: 2)
        let a = Point(x: 0.4, y: 0.5), b = Point(x: 0.52, y: 0.5)
        var t = pad.t
        func frame(_ touches: [Touch]) -> TouchFrame { t += 0.01; return TouchFrame(timestamp: t, touches: touches) }
        var frames: [TouchFrame] = []
        for _ in 0..<6 { frames.append(frame([Touch(id: 20, phase: .touching, position: a, pressure: 20)])) }
        for _ in 0..<10 {
            frames.append(frame([Touch(id: 20, phase: .touching, position: a, pressure: 20),
                                 Touch(id: 21, phase: .touching, position: b, pressure: 20)]))
        }
        for _ in 0..<5 { frames.append(frame([Touch(id: 21, phase: .touching, position: b, pressure: 20)])) }
        frames.append(frame([]))
        pad.frames = frames
        #expect(run(&flow, pad).contains(.confirmLayout))
    }

    @Test func twoFingerDragDoesNotConfirm() {
        var (flow, pad) = adjusting(count: 2)
        var t = pad.t
        var frames: [TouchFrame] = []
        for i in 0..<15 {
            t += 0.01
            let dx = Double(i) * 0.02
            frames.append(TouchFrame(timestamp: t, touches: [
                Touch(id: 30, phase: .touching, position: Point(x: 0.3 + dx, y: 0.5), pressure: 20),
                Touch(id: 31, phase: .touching, position: Point(x: 0.4 + dx, y: 0.5), pressure: 20),
            ]))
        }
        frames.append(TouchFrame(timestamp: t + 0.01, touches: []))
        pad.frames = frames
        #expect(!run(&flow, pad).contains(.confirmLayout))
    }

    @Test func dragAppsIntoPanesCompletes() {
        var (flow, pad) = adjusting(count: 2, apps: 3)
        pad.twoFingerTap()
        _ = run(&flow, pad)
        pad = Pad(t: pad.t, id: pad.id)

        // Pick app 0 in the strip, drop it in the left pane.
        pad.hold(Point(x: 0.1, y: 0.5), force: 20)
        pad.hold(Point(x: 0.1, y: 0.5), force: 200, steps: 2)
        pad.move(from: Point(x: 0.1, y: 0.5), to: Point(x: 0.4, y: 0.5), force: 200)
        pad.hold(Point(x: 0.4, y: 0.5), force: 20)
        pad.lift()
        // Scroll down to app 1, drop it in the right pane.
        pad.move(from: Point(x: 0.1, y: 0.6), to: Point(x: 0.1, y: 0.5), force: 20, steps: 10)
        pad.hold(Point(x: 0.1, y: 0.5), force: 200, steps: 2)
        pad.move(from: Point(x: 0.1, y: 0.5), to: Point(x: 0.85, y: 0.5), force: 200)
        pad.lift()

        let events = run(&flow, pad)
        #expect(events.contains(.dropApp(app: 0, pane: 0)))
        #expect(events.contains(.highlightApp(1)))
        #expect(events.contains(.dropApp(app: 1, pane: 1)))
        #expect(events.last == .complete([0: 0, 1: 1]))
    }

    @Test func droppingOutsidePanesCancels() {
        var (flow, pad) = adjusting(count: 2)
        pad.twoFingerTap()
        _ = run(&flow, pad)
        pad = Pad(t: pad.t, id: pad.id)
        pad.hold(Point(x: 0.1, y: 0.5), force: 200, steps: 2)
        pad.hold(Point(x: 0.1, y: 0.5), force: 20)
        pad.lift()
        #expect(run(&flow, pad).contains(.cancelDrag))
        #expect(flow.assignments.isEmpty)
    }

    @Test func fewerAppsThanPanesCompletesEarly() {
        #expect(TilingFlow(appCount: 1).panesToFill == 1)
    }
}

@Suite struct TilingFitTests {
    @Test func untouchedWhenEverythingFits() {
        var layout = TilingLayout(count: 2)
        layout.move(.vertical, to: 0.4)
        #expect(layout.fitted(to: [0: Size(width: 0.3, height: 0.5), 1: Size(width: 0.3, height: 0.5)]) == layout)
    }

    @Test func dividerMovesToFitTheWideWindow() {
        var layout = TilingLayout(count: 2)
        layout.move(.vertical, to: 0.7)
        // Right window needs 40 % of the screen: the divider moves from 0.7 to 0.6.
        let fitted = layout.fitted(to: [1: Size(width: 0.4, height: 0.3)])
        #expect(abs(fitted.splitX - 0.6) < 1e-9)
    }

    @Test func threePaneUsesWidestRightWindowAndRowHeights() {
        let fitted = TilingLayout(count: 3).fitted(to: [
            1: Size(width: 0.55, height: 0.3), 2: Size(width: 0.2, height: 0.7),
        ])
        #expect(abs(fitted.splitX - 0.45) < 1e-9)
        #expect(abs(fitted.splitY - 0.3) < 1e-9)
    }

    @Test func gridUsesBothWindowsInEachColumn() {
        let fitted = TilingLayout(count: 4).fitted(to: [
            0: Size(width: 0.2, height: 0.2), 2: Size(width: 0.6, height: 0.2),
        ])
        #expect(abs(fitted.splitX - 0.6) < 1e-9)
    }

    @Test func impossibleFitSharesOverflowProportionally() {
        let fitted = TilingLayout(count: 2).fitted(to: [0: Size(width: 0.6, height: 0), 1: Size(width: 0.6, height: 0)])
        #expect(abs(fitted.splitX - 0.5) < 1e-9)
        let skewed = TilingLayout(count: 2).fitted(to: [0: Size(width: 0.9, height: 0), 1: Size(width: 0.3, height: 0)])
        #expect(abs(skewed.splitX - 0.75) < 1e-9)
    }
}
