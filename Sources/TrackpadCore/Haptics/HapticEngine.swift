import AppKit
import Foundation

/// Distinct haptic waveforms. Raw values are MTActuator actuation IDs.
public enum HapticPattern: Int32, Sendable, Codable, CaseIterable {
    /// Barely noticeable, good for scroll detents.
    case tick = 1
    case weak = 3
    case medium = 4
    case strong = 6
    /// Feels like a firm click.
    case click = 15
    case heavyClick = 16

    public var displayName: String {
        switch self {
        case .tick: "Tick"
        case .weak: "Weak"
        case .medium: "Medium"
        case .strong: "Strong"
        case .click: "Click"
        case .heavyClick: "Heavy Click"
        }
    }

    /// Closest public-API equivalent, used when the private actuator is unavailable.
    var fallback: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .tick, .weak: .alignment
        case .medium: .levelChange
        case .strong, .click, .heavyClick: .generic
        }
    }
}

/// Drives the Taptic Engine under the trackpad.
///
/// Uses the private MTActuator API for direct, app-independent feedback and
/// falls back to `NSHapticFeedbackManager` (which only fires while the
/// finger is on the trackpad and the app is allowed to) if it is missing.
public final class HapticEngine: @unchecked Sendable {
    public static let shared = HapticEngine()

    private let queue = DispatchQueue(label: "TrackpadProMax.haptics", qos: .userInteractive)
    private var actuators: [CFTypeRef] = []
    private var didOpen = false

    /// True when at least one actuator was opened through the private API.
    public var usesPrivateActuator: Bool {
        queue.sync {
            openIfNeeded()
            return !actuators.isEmpty
        }
    }

    private init() {}

    public func play(_ pattern: HapticPattern) {
        queue.async { self.actuate(pattern) }
    }

    /// Plays patterns back to back with `interval` seconds between them.
    public func play(_ patterns: [HapticPattern], interval: TimeInterval = 0.08) {
        for (index, pattern) in patterns.enumerated() {
            queue.asyncAfter(deadline: .now() + interval * Double(index)) { self.actuate(pattern) }
        }
    }

    private func actuate(_ pattern: HapticPattern) {
        openIfNeeded()
        guard let bridge = MultitouchBridge.shared, !actuators.isEmpty else {
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(pattern.fallback, performanceTime: .now)
            }
            return
        }
        for actuator in actuators {
            _ = bridge.actuatorActuate(actuator, pattern.rawValue, 0, 0, 0)
        }
    }

    private func openIfNeeded() {
        guard !didOpen else { return }
        didOpen = true
        guard let bridge = MultitouchBridge.shared, let found = bridge.deviceList() else { return }
        for device in found.devices {
            guard let id = bridge.deviceID(of: device),
                  let actuator = bridge.actuatorCreate(id)?.takeRetainedValue(),
                  bridge.actuatorOpen(actuator) == 0
            else { continue }
            actuators.append(actuator)
        }
    }

    deinit {
        guard let bridge = MultitouchBridge.shared else { return }
        for actuator in actuators { _ = bridge.actuatorClose(actuator) }
    }
}
