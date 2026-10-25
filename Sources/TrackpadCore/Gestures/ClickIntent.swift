import Foundation

/// Decides, while a system click is being held back, whether the user means a
/// normal click or is pushing on toward a bound deep press.
///
/// Fed with force samples from the moment the click was held:
/// - force reaches `target` → `.deepPress` (the bound gesture takes over),
/// - force falls back off its peak → `.click` (the user eased off),
/// - force stays flat for `plateauDuration` → `.click` (holding / dragging).
public struct ClickIntent: Sendable {
    public enum Decision: Sendable, Equatable {
        case click
        case deepPress
    }

    /// Force at which the bound press fires.
    public var target: Double
    /// Fraction of the peak force below which the press counts as released.
    public var dropRatio = 0.85
    /// Force must move by more than this fraction to count as still rising.
    public var plateauTolerance = 0.08
    public var plateauDuration: TimeInterval = 0.2

    private var peak = 0.0
    private var plateauForce = 0.0
    private var plateauStart: TimeInterval?

    public init(target: Double) {
        self.target = target
    }

    public mutating func update(force: Double, at time: TimeInterval) -> Decision? {
        if force >= target { return .deepPress }
        if peak > 0, force < peak * dropRatio { return .click }
        peak = max(peak, force)

        if let start = plateauStart, abs(force - plateauForce) <= plateauForce * plateauTolerance {
            if time - start >= plateauDuration { return .click }
        } else {
            plateauStart = time
            plateauForce = force
        }
        return nil
    }
}
