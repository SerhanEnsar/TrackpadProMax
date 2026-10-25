import AppKit
import Observation
import TrackpadCore

/// Central state shared by the menu, settings and visualizer.
@MainActor
@Observable
final class AppModel {
    struct FiredGesture: Identifiable {
        let id = UUID()
        let date = Date()
        let trigger: Trigger
        let actionName: String?
    }

    var configuration: Configuration {
        didSet { configurationChanged(from: oldValue) }
    }
    private(set) var frontmostApp: NSRunningApplication?
    private(set) var recentGestures: [FiredGesture] = []
    private(set) var hasAccessibility = ActionPerformer.hasAccessibilityPermission
    var saveError: String?

    let isMultitouchAvailable = TouchStream.shared.isAvailable

    @ObservationIgnored let store = ConfigurationStore()
    @ObservationIgnored private(set) var pipeline: TouchPipeline!
    @ObservationIgnored private var dispatcher: GestureDispatcher!
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private let modeHUD = ModeHUD()

    init() {
        configuration = store.load()
        dispatcher = GestureDispatcher(
            configuration: configuration,
            perform: { ActionPerformer.shared.perform($0) },
            haptic: { HapticEngine.shared.play($0) }
        )
        pipeline = TouchPipeline(settings: configuration.gestures) { [weak self] event in
            self?.handle(event)
        }
        ActionPerformer.shared.onNextMode = { [weak self] in self?.selectNextMode() }

        frontmostApp = NSWorkspace.shared.frontmostApplication
        dispatcher.frontmostBundleID = frontmostApp?.bundleIdentifier
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        })

        registerHotKey()
        pipeline.start()
        watchAccessibilityPermission()
    }

    var activeMode: Mode { configuration.activeMode }

    // MARK: - Actions

    func selectNextMode() {
        configuration.selectNextMode()
        announceMode()
    }

    func selectMode(_ id: UUID) {
        guard id != configuration.activeModeID else { return }
        configuration.activeModeID = id
        announceMode()
    }

    func requestAccessibility() {
        ActionPerformer.requestAccessibilityPermission()
    }

    func resetToDefaults() {
        configuration = .defaults
    }

    // MARK: - Internals

    private func handle(_ event: GestureEvent) {
        let binding = activeMode.binding(for: event.trigger, bundleID: dispatcher.frontmostBundleID)
        record(event.trigger, action: configuration.isEnabled ? binding?.action.displayName : nil)
        dispatcher.handle(event)
    }

    private func record(_ trigger: Trigger, action: String?) {
        recentGestures.insert(FiredGesture(trigger: trigger, actionName: action), at: 0)
        if recentGestures.count > 20 { recentGestures.removeLast() }
    }

    private func announceMode() {
        HapticEngine.shared.play([.weak, .strong])
        modeHUD.show(name: activeMode.name, symbol: activeMode.symbol)
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        // Ignore ourselves so opening Settings keeps the previous app's profile in view.
        guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontmostApp = app
        dispatcher.frontmostBundleID = app?.bundleIdentifier
    }

    private func configurationChanged(from old: Configuration) {
        dispatcher.configuration = configuration
        if old.gestures != configuration.gestures { pipeline.settings = configuration.gestures }
        if old.modeHotkey != configuration.modeHotkey { registerHotKey() }
        do {
            try store.save(configuration)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = configuration.modeHotkey.flatMap { combo in
            HotKey(combo) { [weak self] in self?.selectNextMode() }
        }
    }

    private func refreshAccessibility() {
        hasAccessibility = ActionPerformer.hasAccessibilityPermission
        if hasAccessibility {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    /// The Accessibility grant does not post a notification, so poll while it is missing.
    private func watchAccessibilityPermission() {
        guard !hasAccessibility else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
    }
}
