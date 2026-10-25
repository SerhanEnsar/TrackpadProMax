import AppKit
import ApplicationServices
import TrackpadCore

/// Moves and resizes other apps' windows through the Accessibility API.
@MainActor
enum WindowTiler {
    struct App: Identifiable {
        let id: pid_t
        let name: String
        let icon: NSImage
    }

    /// Every running regular app. Apps with windows on screen come first, in
    /// front-to-back order; Accessibility only sees the current Space, so we
    /// do not filter on it (full-screen and other-desktop apps are included).
    static func runningApps() -> [App] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var order: [pid_t] = []
        for info in windowList where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, !order.contains(pid) { order.append(pid) }
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }
        let rank = { (pid: pid_t) in order.firstIndex(of: pid) ?? Int.max }
        return apps
            .enumerated()
            .sorted { (rank($0.element.processIdentifier), $0.offset) < (rank($1.element.processIdentifier), $1.offset) }
            .map { App(id: $0.element.processIdentifier, name: $0.element.localizedName ?? "App", icon: $0.element.icon ?? NSImage()) }
    }

    /// Puts each app's main window into its pane (normalized, y down) on the
    /// main screen, one app at a time, then brings them forward in order.
    static func tile(_ placements: [(pid: pid_t, pane: Rect)]) {
        guard let screen = NSScreen.main else { return }
        let frames = placements.map { (pid: $0.pid, frame: axFrame(for: $0.pane, on: screen)) }
        Task { @MainActor in
            // Stage Manager keeps only the active app on stage, so a tiled
            // layout would collapse to one window. Turn it off first.
            if StageManager.isOn {
                StageManager.turnOff()
                try? await Task.sleep(for: .milliseconds(900))
            }
            var placed: [(pid: pid_t, window: AXUIElement)] = []
            for placement in frames {
                if let window = await place(pid: placement.pid, frame: placement.frame) {
                    placed.append((placement.pid, window))
                }
            }
            await bringToFront(placed)
        }
    }

    /// Pane → rect in Accessibility coordinates (top-left origin of the primary screen).
    private static func axFrame(for pane: Rect, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let width = pane.width * visible.width
        let height = pane.height * visible.height
        let x = visible.minX + pane.x * visible.width
        let topY = visible.maxY - pane.y * visible.height
        return CGRect(x: x, y: primaryHeight - topY, width: width, height: height)
    }

    /// Brings every tiled window in front of other apps, first pane on top.
    ///
    /// Since macOS 14 an app may only activate another if it is active itself
    /// (cooperative activation). So we activate ourselves, then hand
    /// activation down the chain: us → last pane's app → … → first pane's app.
    private static func bringToFront(_ placed: [(pid: pid_t, window: AXUIElement)]) async {
        NSApp.activate()
        try? await Task.sleep(for: .milliseconds(80))
        var previous = NSRunningApplication.current
        for item in placed.reversed() {
            guard let app = NSRunningApplication(processIdentifier: item.pid) else { continue }
            AXUIElementPerformAction(item.window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(item.window, kAXMainAttribute as CFString, kCFBooleanTrue)
            if previous == NSRunningApplication.current { NSApp.yieldActivation(to: app) }
            let activated = app.activate(from: previous, options: [])
            if !activated {
                // Fallback: Accessibility can still mark the app frontmost.
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(item.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            }
            Log.action.notice("Tiling: raised \(app.localizedName ?? "?", privacy: .public) (activated: \(activated, privacy: .public))")
            previous = app
            try? await Task.sleep(for: .milliseconds(140))
        }
    }

    /// Returns the window it placed, so it can be raised afterwards.
    private static func place(pid: pid_t, frame: CGRect) async -> AXUIElement? {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return nil }
        let name = running.localizedName ?? "pid \(pid)"
        running.unhide()
        let app = AXUIElementCreateApplication(pid)

        var window = mainWindow(of: app)
        if window == nil, let url = running.bundleURL {
            // Its windows are on another Space or hidden: bring the app over.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            try? await Task.sleep(for: .milliseconds(450))
            window = mainWindow(of: app)
        }
        guard let window else {
            Log.action.error("Tiling: \(name, privacy: .public) has no window we can reach")
            return nil
        }

        if bool(window, "AXFullScreen") == true {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            try? await Task.sleep(for: .milliseconds(1100))
        }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        for attempt in 0..<2 {
            set(window, frame)
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 120 : 250))
            let actual = currentFrame(window)
            let ok = actual.map { abs($0.minX - frame.minX) < 20 && abs($0.minY - frame.minY) < 20
                && abs($0.width - frame.width) < 20 && abs($0.height - frame.height) < 20 } ?? false
            Log.action.notice("""
            Tiled \(name, privacy: .public) to \(String(describing: frame), privacy: .public) \
            (actual \(String(describing: actual), privacy: .public), attempt \(attempt + 1, privacy: .public))
            """)
            if ok { break }
        }
        return window
    }

    private static func set(_ window: AXUIElement, _ frame: CGRect) {
        var position = frame.origin, size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Position, size, position again: some apps shift when resized.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if status != .success { Log.action.error("Tiling: resize refused (\(status.rawValue, privacy: .public))") }
    }

    private static func currentFrame(_ window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    /// The app's focused/main window, else its first window, skipping
    /// anything that is not a normal window (e.g. Finder's desktop).
    private static func mainWindow(of app: AXUIElement) -> AXUIElement? {
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
                candidates.append(value as! AXUIElement)
            }
        }
        var list: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success {
            candidates += list as? [AXUIElement] ?? []
        }
        return candidates.first(where: isStandardWindow)
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXStandardWindowSubrole as String)
    }
}

/// Stage Manager's on/off switch, the same preference Control Center flips.
@MainActor
enum StageManager {
    private static let domain = "com.apple.WindowManager" as CFString
    private static let key = "GloballyEnabled" as CFString

    static var isOn: Bool {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? Bool) ?? false
    }

    static func turnOff() {
        CFPreferencesSetAppValue(key, kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        Log.action.notice("Tiling: turned Stage Manager off")
    }
}
