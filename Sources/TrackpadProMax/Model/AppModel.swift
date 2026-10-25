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
    @ObservationIgnored private var discoveryHotKey: HotKey?
    @ObservationIgnored private let discoveryHUD = DiscoveryHUD()
    @ObservationIgnored private var discoveryPolicy = DiscoveryPolicy()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var clickMonitors: [Any] = []
    @ObservationIgnored private let modeHUD = ModeHUD()
    @ObservationIgnored private let clickGate = ClickGate()
    @ObservationIgnored private var heldClickTarget: Double?
    @ObservationIgnored private var interaction: InteractionController!
    /// The gesture mode to return to when a control surface closes.
    @ObservationIgnored private var lastGestureModeID: UUID?
    /// A 4-finger tap closes an overlay, but waits to see if it is a double tap.
    @ObservationIgnored private var pendingOverlayClose: DispatchWorkItem?

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
        ActionPerformer.shared.onModeWheel = { [weak self] in self?.toggleModeWheel() }

        // Never start inside a control surface: it freezes the cursor.
        if configuration.activeMode.isControlSurface, let first = configuration.gestureModes.first {
            configuration.activeModeID = first.id
        }
        lastGestureModeID = configuration.activeModeID
        interaction = InteractionController(pipeline: pipeline)
        interaction.deepPressThreshold = configuration.gestures.hardThreshold
        interaction.onSelectMode = { [weak self] id in self?.selectMode(id) }
        interaction.onSurfaceIdle = { [weak self] in self?.leaveControlSurface() }

        frontmostApp = NSWorkspace.shared.frontmostApplication
        dispatcher.frontmostBundleID = frontmostApp?.bundleIdentifier
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        })

        registerHotKey()
        monitorPhysicalClicks()
        clickGate.onPhysicalClick = { [pipeline] in pipeline?.registerPhysicalClick() }
        clickGate.shouldHold = { [weak self] in self?.shouldHoldClick() ?? false }
        clickGate.onHold = { [weak self] in self?.watchHeldClick() }
        if hasAccessibility { clickGate.start() }
        pipeline.start()
        watchAccessibilityPermission()
    }

    var activeMode: Mode { configuration.activeMode }

    // MARK: - Actions

    /// Cycles through gesture modes (control surfaces are picked from the wheel).
    func selectNextMode() {
        let modes = configuration.gestureModes
        guard !modes.isEmpty else { return }
        let index = modes.firstIndex { $0.id == configuration.activeModeID } ?? -1
        selectMode(modes[(index + 1) % modes.count].id)
    }

    func selectMode(_ id: UUID) {
        guard let mode = configuration.modes.first(where: { $0.id == id }) else { return }
        if mode.isControlSurface {
            guard id != configuration.activeModeID else { return }
            configuration.activeModeID = id
            interaction.enterSurface(mode)
            HapticEngine.shared.play([.weak, .strong])
        } else {
            interaction.exitSurface()
            lastGestureModeID = id
            guard id != configuration.activeModeID else { return }
            configuration.activeModeID = id
            announceMode()
        }
    }

    func toggleModeWheel() {
        guard configuration.isEnabled else { return }
        interaction.toggleWheel(modes: configuration.modes, activeID: configuration.activeModeID)
    }

    /// Back to the gesture mode that was active before the control surface.
    func leaveControlSurface() {
        let target = lastGestureModeID.flatMap { id in configuration.gestureModes.first { $0.id == id } }
            ?? configuration.gestureModes.first
        if let target {
            selectMode(target.id)
        } else {
            interaction.exitSurface()
        }
    }

    /// Mode whose bindings still work while an overlay owns the trackpad
    /// (only to reopen or close the mode wheel).
    private var shortcutMode: Mode? {
        configuration.modes.first { $0.id == lastGestureModeID } ?? configuration.gestureModes.first
    }

    /// Shows the gesture card for the frontmost app, even if it has no gestures.
    func showDiscoveryCard() {
        let app = frontmostApp
        let bindings = activeMode.effectiveBindings(for: app?.bundleIdentifier)
        presentDiscovery(app: app, bindings: bindings)
    }

    func unmuteDiscovery(_ bundleID: String) {
        configuration.discovery.mutedApps.removeAll { $0 == bundleID }
    }

    func requestAccessibility() {
        ActionPerformer.requestAccessibilityPermission()
    }

    func resetToDefaults() {
        configuration = .defaults
    }

    // MARK: - Internals

    private func handle(_ event: GestureEvent) {
        if interaction.isActive {
            // The overlay owns the trackpad; only the wheel gesture and the
            // 4-finger "close" tap get through.
            guard configuration.isEnabled else { return }
            if shortcutMode?.binding(for: event.trigger, bundleID: nil)?.action == .modeWheel {
                pendingOverlayClose?.cancel()
                pendingOverlayClose = nil
                toggleModeWheel()
            } else if case .tap(fingers: 4, count: 1, _) = event.trigger {
                pendingOverlayClose?.cancel()
                let close = DispatchWorkItem { [weak self] in self?.interaction.escape() }
                pendingOverlayClose = close
                DispatchQueue.main.asyncAfter(deadline: .now() + configuration.gestures.doubleTapInterval, execute: close)
            }
            return
        }
        let binding = activeMode.binding(for: event.trigger, bundleID: dispatcher.frontmostBundleID)
        record(event.trigger, action: configuration.isEnabled ? binding?.action.displayName : nil)
        if configuration.isEnabled, binding != nil, case .press = event.trigger, clickGate.consumeHeldClick() {
            Log.action.notice("Swallowed the click under \(event.trigger.displayName, privacy: .public)")
        }
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
        announceGestures(in: app)
    }

    /// Shows the discovery card the first time a freshly launched app comes forward.
    private func announceGestures(in app: NSRunningApplication?) {
        guard let app, configuration.isEnabled, !activeMode.isControlSurface else { return }
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        discoveryPolicy.prune(keeping: running)
        guard let bindings = discoveryPolicy.gesturesToAnnounce(
            bundleID: app.bundleIdentifier, processID: app.processIdentifier,
            mode: activeMode, settings: configuration.discovery
        ) else { return }
        presentDiscovery(app: app, bindings: bindings)
    }

    private func presentDiscovery(app: NSRunningApplication?, bindings: [GestureBinding]) {
        let bundleID = app?.bundleIdentifier
        discoveryHUD.show(
            app: app, modeName: activeMode.name, bindings: bindings,
            duration: configuration.discovery.displayDuration,
            onMute: bundleID.map { id in { [weak self] in self?.configuration.discovery.mutedApps.append(id) } }
        )
    }

    private func configurationChanged(from old: Configuration) {
        if !configuration.isEnabled, interaction?.isActive == true {
            interaction.closeWheel()
            leaveControlSurface()
        }
        dispatcher.configuration = configuration
        if old.gestures != configuration.gestures {
            pipeline.settings = configuration.gestures
            interaction?.deepPressThreshold = configuration.gestures.hardThreshold
        }
        if old.modeHotkey != configuration.modeHotkey || old.discovery.hotkey != configuration.discovery.hotkey {
            registerHotKey()
        }
        do {
            try store.save(configuration)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Hold the system click if a medium or hard press is bound for the current
    /// finger count and position, so the press can replace the click.
    private func shouldHoldClick() -> Bool {
        guard configuration.isEnabled, !interaction.isActive else { return false }
        let touches = pipeline.latestFrame.activeTouches
        guard !touches.isEmpty else { return false }
        let center = Point(
            x: touches.map(\.position.x).reduce(0, +) / Double(touches.count),
            y: touches.map(\.position.y).reduce(0, +) / Double(touches.count)
        )
        let zone = Zone.classify(center, margin: configuration.gestures.zoneMargin)
        let tiers = activeMode.effectiveBindings(for: dispatcher.frontmostBundleID).compactMap { binding -> PressTier? in
            guard case let .press(tier, fingers, bindingZone) = binding.trigger,
                  tier >= .medium, fingers == touches.count, bindingZone.matches(zone) else { return nil }
            return tier
        }
        // The shallowest bound press decides how deep the user has to go.
        heldClickTarget = tiers.min().map { configuration.gestures.threshold(for: $0) }
        return heldClickTarget != nil
    }

    /// Hands the held click over to `ClickIntent`: deliver it as soon as the
    /// user eases off or holds still; a deep press is handled by the gesture.
    private func watchHeldClick() {
        let target = heldClickTarget ?? configuration.gestures.hardThreshold
        pipeline.watchClickIntent(target: target) { [weak self] decision in
            guard let self, decision == .click else { return }
            clickGate.releaseHeldClick()
        }
    }

    /// Mouse-down events tell the recognizer when the trackpad really clicked.
    /// Global monitors see other apps' events, the local one sees ours.
    private func monitorPhysicalClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let pipeline = pipeline!
        // Skip clicks the click gate replays; it reports the real ones itself.
        let isReal = { (event: NSEvent) in
            event.cgEvent?.getIntegerValueField(.eventSourceUserData) != ClickGate.syntheticMarker
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            if isReal(event) { pipeline.registerPhysicalClick() }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            if isReal(event) { pipeline.registerPhysicalClick() }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = configuration.modeHotkey.flatMap { combo in
            HotKey(combo) { [weak self] in self?.toggleModeWheel() }
        }
        discoveryHotKey?.unregister()
        discoveryHotKey = configuration.discovery.hotkey.flatMap { combo in
            HotKey(combo) { [weak self] in self?.showDiscoveryCard() }
        }
    }

    private func refreshAccessibility() {
        hasAccessibility = ActionPerformer.hasAccessibilityPermission
        if hasAccessibility {
            clickGate.start()
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
