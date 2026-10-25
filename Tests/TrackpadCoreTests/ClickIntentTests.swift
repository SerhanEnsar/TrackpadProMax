import Testing
@testable import TrackpadCore

@Suite struct ClickIntentTests {
    /// Feeds force samples at 100 Hz, returns the first decision and when it came.
    func run(_ forces: [Double], target: Double = 750) -> (ClickIntent.Decision, Int)? {
        var intent = ClickIntent(target: target)
        for (index, force) in forces.enumerated() {
            if let decision = intent.update(force: force, at: Double(index) * 0.01) {
                return (decision, index)
            }
        }
        return nil
    }

    @Test func reachingTargetIsDeepPress() {
        #expect(run([200, 400, 600, 800])?.0 == .deepPress)
    }

    @Test func easingOffBeforeTargetIsClickRightAway() {
        let result = run([200, 300, 400, 380, 330, 250])
        #expect(result?.0 == .click)
        #expect(result?.1 == 4, "fires on the first sample below 85 % of the peak")
    }

    @Test func holdingSteadyIsClick() {
        let result = run(Array(repeating: 220, count: 40))
        #expect(result?.0 == .click)
        #expect(result?.1 == 20)
    }

    @Test func steadyRiseIsNotPlateau() {
        // Slow ramp to a hard press must not be mistaken for holding.
        let ramp = stride(from: 200.0, through: 760, by: 14).map { $0 }
        #expect(run(ramp)?.0 == .deepPress)
    }

    @Test func smallWobbleStillCountsAsHolding() {
        let wobble = (0..<40).map { 220 + Double($0 % 2) * 10 }
        #expect(run(wobble)?.0 == .click)
    }
}
