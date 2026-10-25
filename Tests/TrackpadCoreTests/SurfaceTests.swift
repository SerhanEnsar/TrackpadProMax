import Foundation
import Testing
@testable import TrackpadCore

/// Feeds one finger along `path` at 100 Hz, then lifts.
private func slide(_ path: [Point], id: Int = 1, start: Double = 0) -> [TouchFrame] {
    var frames = path.enumerated().map { index, point in
        TouchFrame(timestamp: start + Double(index) * 0.01, touches: [Touch(id: id, phase: .touching, position: point)])
    }
    frames.append(TouchFrame(timestamp: start + Double(path.count) * 0.01, touches: []))
    return frames
}

private func line(from a: Point, to b: Point, steps: Int = 30) -> [Point] {
    (0...steps).map { i in
        let t = Double(i) / Double(steps)
        return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

@Suite struct RadialSelectorTests {
    func run(_ selector: inout RadialSelector, _ frames: [TouchFrame]) -> [RadialSelector.Event] {
        frames.flatMap { selector.process($0) }
    }

    @Test func slideUpHighlightsTopItem() {
        var wheel = RadialSelector(itemCount: 4)
        let events = run(&wheel, slide(line(from: Point(x: 0.5, y: 0.4), to: Point(x: 0.5, y: 0.7))))
        #expect(events.first == .highlight(0))
        #expect(wheel.highlighted == 0)
    }

    @Test func slideRightHighlightsSecondOfFour() {
        var wheel = RadialSelector(itemCount: 4)
        _ = run(&wheel, slide(line(from: Point(x: 0.3, y: 0.5), to: Point(x: 0.6, y: 0.5))))
        #expect(wheel.highlighted == 1)
    }

    @Test func highlightSurvivesLiftAndTapConfirms() {
        var wheel = RadialSelector(itemCount: 4)
        _ = run(&wheel, slide(line(from: Point(x: 0.5, y: 0.5), to: Point(x: 0.5, y: 0.2)), start: 0))
        #expect(wheel.highlighted == 2)
        let tap = run(&wheel, slide(Array(repeating: Point(x: 0.4, y: 0.4), count: 8), id: 2, start: 2))
        #expect(tap == [.confirm(2)])
    }

    @Test func tapInCenterCancels() {
        var wheel = RadialSelector(itemCount: 3)
        let tap = run(&wheel, slide(Array(repeating: Point(x: 0.5, y: 0.5), count: 8)))
        #expect(tap == [.confirm(nil)])
    }

    @Test func slidingBackToCenterClearsHighlight() {
        var wheel = RadialSelector(itemCount: 4)
        let out = line(from: Point(x: 0.5, y: 0.5), to: Point(x: 0.5, y: 0.75), steps: 20)
        let back = line(from: Point(x: 0.5, y: 0.75), to: Point(x: 0.5, y: 0.5), steps: 20)
        let events = run(&wheel, slide(out + back))
        #expect(events == [.highlight(0), .highlight(nil)])
    }

    @Test func longSlideIsNotTap() {
        var wheel = RadialSelector(itemCount: 4)
        let events = run(&wheel, slide(line(from: Point(x: 0.5, y: 0.5), to: Point(x: 0.5, y: 0.8))))
        #expect(!events.contains { if case .confirm = $0 { true } else { false } })
    }
}

@Suite struct ControlSurfaceTests {
    func run(_ frames: [TouchFrame]) -> [ControlSurfaceTracker.Event] {
        var tracker = ControlSurfaceTracker()
        return frames.flatMap { tracker.process($0) }
    }

    @Test func slideUpOnRightEdgeRaisesValue() {
        let events = run(slide(line(from: Point(x: 0.92, y: 0.3), to: Point(x: 0.92, y: 0.7))))
        #expect(events.first == .began(.right))
        #expect(events.last == .ended(.right))
        let total = events.reduce(0.0) { sum, event in
            if case let .adjust(.right, delta) = event { sum + delta } else { sum }
        }
        #expect(abs(total - 0.4 * 1.4) < 0.001)
    }

    @Test func horizontalMovementOnVerticalBarIsIgnored() {
        let events = run(slide(line(from: Point(x: 0.05, y: 0.5), to: Point(x: 0.2, y: 0.5))))
        #expect(events == [.began(.left), .ended(.left)])
    }

    @Test func middleSlideIsInert() {
        let events = run(slide(line(from: Point(x: 0.5, y: 0.5), to: Point(x: 0.5, y: 0.6))))
        #expect(events.isEmpty)
    }

    @Test func middleQuickTouchIsCenterTap() {
        let events = run(slide(Array(repeating: Point(x: 0.5, y: 0.5), count: 10)))
        #expect(events == [.centerTap])
    }

    @Test func musicLayoutIsMusic() {
        #expect(ControlSurfaceLayout.music.isMusic)
        #expect(ControlSurfaceLayout().isMusic, "default Control layout has a media bar")
        #expect(!ControlSurfaceLayout(left: .volume, right: .brightness, top: .none, bottom: .keyboardBacklight).isMusic)
    }

    @Test func quickTouchOnTopIsTap() {
        let events = run(slide(Array(repeating: Point(x: 0.5, y: 0.95), count: 10)))
        #expect(events == [.began(.top), .tap(.top), .ended(.top)])
    }

    @Test func flickOnTopIsOneSwipe() {
        let events = run(slide(line(from: Point(x: 0.3, y: 0.92), to: Point(x: 0.7, y: 0.92))))
        let swipes = events.filter { if case .swipe = $0 { true } else { false } }
        #expect(swipes == [.swipe(.top, 1)])
    }

    @Test func layoutDecodesMissingKeysAsDefaults() throws {
        let layout = try JSONDecoder().decode(ControlSurfaceLayout.self, from: Data(#"{"right":"brightness"}"#.utf8))
        #expect(layout.right == .brightness)
        #expect(layout.left == ControlSurfaceLayout().left)
    }
}
