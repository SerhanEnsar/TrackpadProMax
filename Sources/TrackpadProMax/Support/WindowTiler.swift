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
            for placement in frames {
                await place(pid: placement.pid, frame: placement.frame)
            }
            // Raise in reverse so the first pane's app ends up frontmost. A
            // background app cannot activate others directly (cooperative
            // activation), but Accessibility can mark an app frontmost.
            for placement in frames.reversed() {
                AXUIElementSetAttributeValue(
                    AXUIElementCreateApplication(placement.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue
                )
                try? await Task.sleep(for: .milliseconds(60))
            }
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

    private static func place(pid: pid_t, frame: CGRect) async {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return }
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
            return
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
            if ok { return }
        }
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

    private static func mainWindow(of app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
                return (value as! AXUIElement)
            }
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return (value as? [AXUIElement])?.first
    }
}
