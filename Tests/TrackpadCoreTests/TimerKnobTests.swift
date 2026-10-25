import Foundation
import Testing
@testable import TrackpadCore

@Suite struct TimerKnobTests {
    /// One finger circling the pad center by `degrees` (positive = clockwise).
    func circle(degrees: Double, from startDegrees: Double = 0, steps: Int = 60) -> [TouchFrame] {
        var frames = (0...steps).map { i -> TouchFrame in
            let a = (startDegrees + degrees * Double(i) / Double(steps)) * .pi / 180
            let p = Point(x: 0.5 + sin(a) * 0.3 / 1.6, y: 0.5 + cos(a) * 0.3)
            return TouchFrame(timestamp: Double(i) * 0.01, touches: [Touch(id: 1, phase: .touching, position: p)])
        }
        frames.append(TouchFrame(timestamp: Double(steps + 1) * 0.01, touches: []))
        return frames
    }

    func tap(at p: Point) -> [TouchFrame] {
        (0..<8).map { TouchFrame(timestamp: 5 + Double($0) * 0.01, touches: [Touch(id: 9, phase: .touching, position: p)]) }
            + [TouchFrame(timestamp: 5.1, touches: [])]
    }

    @Test func clockwiseTurnAddsMinutes() {
        var knob = TimerKnob(minutes: 25)
        _ = circle(degrees: 90).flatMap { knob.process($0) }
        #expect(knob.minutes == 28)
    }

    @Test func counterClockwiseRemovesAndClampsAtZero() {
        var knob = TimerKnob(minutes: 2)
        let events = circle(degrees: -200).flatMap { knob.process($0) }
        #expect(knob.minutes == 0)
        #expect(events.last == .minutes(0))
    }

    @Test func turningPastTwelveKeepsCounting() {
        var knob = TimerKnob(minutes: 0)
        _ = circle(degrees: 450, from: 300, steps: 150).flatMap { knob.process($0) }
        #expect(knob.minutes == 15)
    }

    @Test func tapStartsAndCenterTapGoesBack() {
        var knob = TimerKnob(minutes: 10)
        #expect(tap(at: Point(x: 0.8, y: 0.8)).flatMap { knob.process($0) } == [.start(10)])
        #expect(tap(at: Point(x: 0.5, y: 0.5)).flatMap { knob.process($0) } == [.back])
    }
}

@Suite struct GridPickerTests {
    @Test func cellsAreNumberedFromTheTop() {
        let grid = GridPicker(columns: 3, rows: 3)
        #expect(grid.cell(at: Point(x: 0.1, y: 0.9)) == 0)
        #expect(grid.cell(at: Point(x: 0.5, y: 0.5)) == 4)
        #expect(grid.cell(at: Point(x: 0.9, y: 0.1)) == 8)
        #expect(QuickToggle.grid[4] == nil, "middle is Back")
    }

    @Test func slideHighlightsAndTapPicks() {
        var grid = GridPicker(columns: 3, rows: 3)
        let slide = (0...20).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: [
                Touch(id: 1, phase: .touching, position: Point(x: 0.1 + Double(i) * 0.04, y: 0.9)),
            ])
        } + [TouchFrame(timestamp: 0.3, touches: [])]
        #expect(slide.flatMap { grid.process($0) } == [.highlight(0), .highlight(1), .highlight(2)])
        let tap = (0..<8).map { TouchFrame(timestamp: 1 + Double($0) * 0.01, touches: [
            Touch(id: 2, phase: .touching, position: Point(x: 0.5, y: 0.1)),
        ]) } + [TouchFrame(timestamp: 1.1, touches: [])]
        #expect(tap.flatMap { grid.process($0) } == [.highlight(7), .tap(7)])
    }
}
