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

    /// Regular apps that have at least one window, most recently used first.
    static func appsWithWindows() -> [App] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Front-to-back window order; reading owner PIDs needs no permission.
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var order: [pid_t] = []
        for info in windowList where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, !order.contains(pid) { order.append(pid) }
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !windows(of: $0.processIdentifier).isEmpty
        }
        let rank = { (pid: pid_t) in order.firstIndex(of: pid) ?? Int.max }
        return apps
            .sorted { rank($0.processIdentifier) < rank($1.processIdentifier) }
            .map { App(id: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon ?? NSImage()) }
    }

    /// Puts each app's main window into its pane (normalized, y down) on the
    /// main screen's visible area, then brings them forward.
    static func tile(_ placements: [(pid: pid_t, pane: Rect)]) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        for placement in placements {
            let pane = placement.pane
            // Cocoa (bottom-left origin) rect for the pane…
            let width = pane.width * visible.width
            let height = pane.height * visible.height
            let x = visible.minX + pane.x * visible.width
            let topY = visible.maxY - pane.y * visible.height
            // …converted to Accessibility's top-left origin.
            let axOrigin = CGPoint(x: x, y: primaryHeight - topY)
            place(pid: placement.pid, origin: axOrigin, size: CGSize(width: width, height: height))
        }
        // Raise in reverse so the first pane's app ends up frontmost. A
        // background app cannot activate others directly (cooperative
        // activation), but Accessibility can mark an app frontmost.
        for placement in placements.reversed() {
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(placement.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue
            )
        }
    }

    private static func place(pid: pid_t, origin: CGPoint, size: CGSize) {
        let app = AXUIElementCreateApplication(pid)
        guard let window = mainWindow(of: app) else {
            Log.action.error("No window to tile for pid \(pid, privacy: .public)")
            return
        }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        var position = origin, dimensions = size
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &dimensions)!
        // Position, size, position again: some apps shift when resized.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let status = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if status != .success {
            Log.action.error("Resize failed for pid \(pid, privacy: .public): \(status.rawValue, privacy: .public)")
        }
    }

    private static func mainWindow(of app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
                return (value as! AXUIElement)
            }
        }
        return windows(of: app).first
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        windows(of: AXUIElementCreateApplication(pid))
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
