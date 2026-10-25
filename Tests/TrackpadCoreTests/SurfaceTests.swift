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

    @Test func fourFingerTapNeverConfirms() {
        var wheel = RadialSelector(itemCount: 4, highlighted: 1)
        let frames = (0..<8).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: (0..<4).map {
                Touch(id: $0, phase: .touching, position: Point(x: 0.4 + Double($0) * 0.05, y: 0.5))
            })
        } + [TouchFrame(timestamp: 0.1, touches: [])]
        #expect(run(&wheel, frames).isEmpty)
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

    @Test func onlyMusicLayoutNeedsNowPlaying() {
        #expect(ControlSurfaceLayout.music.isMusic, "scrub bar needs Now Playing")
        #expect(ControlSurfaceLayout.music.center == .back)
        #expect(!ControlSurfaceLayout().isMusic, "Control: tracks bar, but the middle is Back")
        #expect(ControlSurfaceLayout().center == .back)
    }

    @Test func oldLayoutsGetCenterFromTheirBars() throws {
        let media = try JSONDecoder().decode(ControlSurfaceLayout.self,
            from: Data(#"{"left":"none","right":"volume","top":"media","bottom":"seek"}"#.utf8))
        #expect(media.center == .nowPlaying)
        let control = try JSONDecoder().decode(ControlSurfaceLayout.self,
            from: Data(#"{"left":"brightness","right":"volume","top":"media","bottom":"keyboardBacklight"}"#.utf8))
        #expect(control.center == .back)
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

    @Test func multiFingerTouchIsIgnored() {
        // A 4-finger tap in the middle must not count as a center tap.
        var frames: [TouchFrame] = (0..<8).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: (0..<4).map {
                Touch(id: $0, phase: .touching, position: Point(x: 0.4 + Double($0) * 0.05, y: 0.5))
            })
        }
        frames.append(TouchFrame(timestamp: 0.1, touches: []))
        #expect(run(frames).isEmpty)
    }

    @Test func secondFingerEndsBarInteraction() {
        var frames = slide(line(from: Point(x: 0.92, y: 0.3), to: Point(x: 0.92, y: 0.5), steps: 10))
        frames.removeLast()
        frames.append(TouchFrame(timestamp: 0.2, touches: [
            Touch(id: 1, phase: .touching, position: Point(x: 0.92, y: 0.5)),
            Touch(id: 2, phase: .touching, position: Point(x: 0.5, y: 0.5)),
        ]))
        frames.append(TouchFrame(timestamp: 0.21, touches: [
            Touch(id: 1, phase: .touching, position: Point(x: 0.92, y: 0.8)),
            Touch(id: 2, phase: .touching, position: Point(x: 0.5, y: 0.5)),
        ]))
        frames.append(TouchFrame(timestamp: 0.3, touches: []))
        let events = run(frames)
        #expect(events.last == .ended(.right))
        #expect(events.filter { $0 == .ended(.right) }.count == 1)
    }

    @Test func deepPressFiresOnceAndIsNotTap() {
        let frames = (0..<10).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: [
                Touch(id: 1, phase: .touching, position: Point(x: 0.92, y: 0.5), pressure: i < 3 ? 100 : 900),
            ])
        } + [TouchFrame(timestamp: 0.1, touches: [])]
        let events = run(frames)
        #expect(events == [.began(.right), .deepPress(.right), .ended(.right)])
    }

    @Test func layoutDecodesMissingKeysAsDefaults() throws {
        let layout = try JSONDecoder().decode(ControlSurfaceLayout.self, from: Data(#"{"right":"brightness"}"#.utf8))
        #expect(layout.right == .brightness)
        #expect(layout.left == ControlSurfaceLayout().left)
    }
}

@Suite struct DevicePickerTests {
    func run(_ picker: inout DevicePicker, _ frames: [TouchFrame]) -> [DevicePicker.Event] {
        frames.flatMap { picker.process($0) }
    }

    @Test func slidingRightStepsAndClampsAtEnd() {
        var picker = DevicePicker(itemCount: 3, highlighted: 0)
        let events = run(&picker, slide(line(from: Point(x: 0.1, y: 0.5), to: Point(x: 0.9, y: 0.5), steps: 40)))
        #expect(events == [.highlight(1), .highlight(2)])
        #expect(picker.highlighted == 2)
    }

    @Test func verticalSlideAdjustsHighlighted() {
        var picker = DevicePicker(itemCount: 3, highlighted: 1)
        let events = run(&picker, slide(line(from: Point(x: 0.5, y: 0.3), to: Point(x: 0.5, y: 0.5), steps: 10)))
        let total = events.reduce(0.0) { sum, event in
            if case let .adjust(1, delta) = event { sum + delta } else { sum }
        }
        #expect(abs(total - 0.2 * 1.4) < 0.001)
    }

    @Test func hardPressActivatesAndTapDismisses() {
        var picker = DevicePicker(itemCount: 2, highlighted: 1)
        let press = (0..<10).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: [
                Touch(id: 1, phase: .touching, position: Point(x: 0.5, y: 0.5), pressure: i < 3 ? 100 : 900),
            ])
        } + [TouchFrame(timestamp: 0.1, touches: [])]
        #expect(run(&picker, press) == [.activate(1)])
        let tap = slide(Array(repeating: Point(x: 0.5, y: 0.5), count: 8), id: 2, start: 1)
        #expect(run(&picker, tap) == [.dismiss])
    }

    @Test func multiFingerIsIgnored() {
        var picker = DevicePicker(itemCount: 2, highlighted: 0)
        let frames = (0..<8).map { i in
            TouchFrame(timestamp: Double(i) * 0.01, touches: (0..<4).map {
                Touch(id: $0, phase: .touching, position: Point(x: 0.3 + Double(i) * 0.05, y: 0.5))
            })
        } + [TouchFrame(timestamp: 0.1, touches: [])]
        #expect(run(&picker, frames).isEmpty)
    }
}
