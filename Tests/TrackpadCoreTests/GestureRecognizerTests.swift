import Testing
@testable import TrackpadCore

@Suite struct TapTests {
    @Test(arguments: 1...4)
    func quickTouchIsTap(fingers: Int) {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(fingers), for: 0.1)
        b.lift()
        #expect(recognize(b.steps) == [.tap(fingers: fingers, count: 1, zone: .center)])
    }

    @Test func longTouchIsNotTap() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1), for: 0.5)
        b.lift()
        #expect(recognize(b.steps).isEmpty)
    }

    @Test func movingTouchIsNotTap() {
        var b = FrameBuilder()
        b.hold([FrameBuilder.finger(0, x: 0.4)], for: 0.05)
        b.hold([FrameBuilder.finger(0, x: 0.5)], for: 0.05)
        b.lift()
        #expect(recognize(b.steps).isEmpty)
    }

    @Test func secondQuickTapIsDoubleTap() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(2), for: 0.08)
        b.lift()
        b.idle(0.1)
        b.hold(FrameBuilder.fingers(2), for: 0.08)
        b.lift()
        #expect(recognize(b.steps) == [
            .tap(fingers: 2, count: 1, zone: .center),
            .tap(fingers: 2, count: 2, zone: .center),
        ])
    }

    @Test func slowSecondTapIsSingle() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1), for: 0.08)
        b.lift()
        b.idle(0.6)
        b.hold(FrameBuilder.fingers(1), for: 0.08)
        b.lift()
        #expect(recognize(b.steps) == [
            .tap(fingers: 1, count: 1, zone: .center),
            .tap(fingers: 1, count: 1, zone: .center),
        ])
    }

    @Test func tapInCornerReportsZone() {
        var b = FrameBuilder()
        b.hold([FrameBuilder.finger(0, x: 0.95, y: 0.95)], for: 0.08)
        b.lift()
        #expect(recognize(b.steps) == [.tap(fingers: 1, count: 1, zone: .topRight)])
    }
}

@Suite struct PressTests {
    let settings = GestureSettings()

    @Test func hardPressFiresImmediatelyOnce() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1, pressure: 200), for: 0.05)
        b.click()
        b.hold(FrameBuilder.fingers(1, pressure: 500), for: 0.05)
        b.hold(FrameBuilder.fingers(1, pressure: 900), for: 0.2)
        b.hold(FrameBuilder.fingers(1, pressure: 100), for: 0.05)
        b.lift()
        #expect(recognize(b.steps) == [.press(tier: .hard, fingers: 1, zone: .center)])
    }

    @Test func mediumPressFiresWhenForceDropsOff() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1, pressure: 500), for: 0.2)
        let beforeRelease = recognize(b.steps)
        b.hold(FrameBuilder.fingers(1, pressure: 20), for: 0.05)
        b.lift()
        #expect(beforeRelease.isEmpty)
        #expect(recognize(b.steps) == [.press(tier: .medium, fingers: 1, zone: .center)])
    }

    @Test func lightPressNeedsPhysicalClick() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1, pressure: 200), for: 0.05)
        b.click()
        b.hold(FrameBuilder.fingers(1, pressure: 200), for: 0.05)
        b.lift()
        #expect(recognize(b.steps) == [.press(tier: .light, fingers: 1, zone: .center)])
    }

    @Test func firmTapWithoutClickIsTapNotPress() {
        // Three-finger taps measured up to ~140 per finger on real hardware.
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(3, pressure: 140), for: 0.08)
        b.lift()
        #expect(recognize(b.steps) == [.tap(fingers: 3, count: 1, zone: .center)])
    }

    @Test func clickIsNotTap() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1, pressure: 60), for: 0.05)
        b.click()
        b.lift()
        #expect(recognize(b.steps).isEmpty)
    }

    @Test func repeatedPressesInOneSession() {
        var b = FrameBuilder()
        for _ in 0..<2 {
            b.hold(FrameBuilder.fingers(1, pressure: 900), for: 0.1)
            b.hold(FrameBuilder.fingers(1, pressure: 5), for: 0.1)
        }
        b.lift()
        #expect(recognize(b.steps) == Array(repeating: .press(tier: .hard, fingers: 1, zone: .center), count: 2))
    }

    @Test func pressSuppressesTap() {
        var b = FrameBuilder()
        b.hold(FrameBuilder.fingers(1, pressure: 900), for: 0.05)
        b.lift()
        #expect(recognize(b.steps) == [.press(tier: .hard, fingers: 1, zone: .center)])
    }

    @Test func dragWithForceIsNotPress() {
        var b = FrameBuilder()
        for step in 0..<20 {
            b.hold([FrameBuilder.finger(0, x: 0.3 + Double(step) * 0.02, pressure: 500)], for: 0.01)
        }
        b.lift()
        #expect(recognize(b.steps).isEmpty)
    }

    @Test func pressInEdgeZone() {
        var b = FrameBuilder()
        b.hold([FrameBuilder.finger(0, x: 0.05, y: 0.5, pressure: 900)], for: 0.05)
        b.lift()
        #expect(recognize(b.steps) == [.press(tier: .hard, fingers: 1, zone: .leftEdge)])
    }
}

@Suite struct ZoneTests {
    @Test(arguments: [
        (Point(x: 0.05, y: 0.95), Zone.topLeft), (Point(x: 0.95, y: 0.95), .topRight),
        (Point(x: 0.05, y: 0.05), .bottomLeft), (Point(x: 0.95, y: 0.05), .bottomRight),
        (Point(x: 0.5, y: 0.95), .topEdge), (Point(x: 0.5, y: 0.05), .bottomEdge),
        (Point(x: 0.05, y: 0.5), .leftEdge), (Point(x: 0.95, y: 0.5), .rightEdge),
        (Point(x: 0.5, y: 0.5), .center),
    ])
    func classify(point: Point, zone: Zone) {
        #expect(Zone.classify(point, margin: 0.18) == zone)
    }

    @Test func anywhereMatchesAll() {
        for zone in Zone.allCases { #expect(Zone.anywhere.matches(zone)) }
        #expect(!Zone.topLeft.matches(.center))
    }
}
