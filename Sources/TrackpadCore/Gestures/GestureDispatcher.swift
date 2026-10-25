import Foundation

/// Maps recognized gestures to bindings and runs them.
///
/// Holds back a single tap for `doubleTapInterval` when a double-tap binding
/// exists for the same fingers, so both can coexist.
@MainActor
public final class GestureDispatcher {
    public var configuration: Configuration
    public var frontmostBundleID: String?
    /// Observers, e.g. for the visualizer or a HUD. Called before the action runs.
    public var onFire: ((GestureEvent, GestureBinding) -> Void)?

    private let perform: (Action) -> Void
    private let haptic: (HapticPattern) -> Void
    private var pendingSingleTap: DispatchWorkItem?

    public init(
        configuration: Configuration,
        perform: @escaping (Action) -> Void,
        haptic: @escaping (HapticPattern) -> Void
    ) {
        self.configuration = configuration
        self.perform = perform
        self.haptic = haptic
    }

    public func handle(_ event: GestureEvent) {
        guard configuration.isEnabled else { return }
        let mode = configuration.activeMode

        if case let .tap(fingers, count, zone) = event.trigger {
            if count == 2 {
                pendingSingleTap?.cancel()
                pendingSingleTap = nil
            } else if mode.binding(for: .tap(fingers: fingers, count: 2, zone: zone), bundleID: frontmostBundleID) != nil {
                let work = DispatchWorkItem { [weak self] in self?.fire(event) }
                pendingSingleTap = work
                DispatchQueue.main.asyncAfter(deadline: .now() + configuration.gestures.doubleTapInterval, execute: work)
                return
            }
        }
        fire(event)
    }

    private func fire(_ event: GestureEvent) {
        guard let binding = configuration.activeMode.binding(for: event.trigger, bundleID: frontmostBundleID) else { return }
        if configuration.hapticOnTrigger { haptic(configuration.triggerHaptic) }
        onFire?(event, binding)
        perform(binding.action)
    }
}
