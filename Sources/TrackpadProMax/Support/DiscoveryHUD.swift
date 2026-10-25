import AppKit
import SwiftUI
import TrackpadCore

/// Floating, non-activating panel in the top-right corner that hosts the
/// `DiscoveryCard`. It never steals focus from the app the user just opened.
@MainActor
final class DiscoveryHUD {
    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?
    private var isHovered = false
    private var displayDuration: TimeInterval = 6

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        app: NSRunningApplication?, modeName: String, bindings: [GestureBinding],
        duration: TimeInterval, onMute: (() -> Void)?
    ) {
        displayDuration = duration
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let card = DiscoveryCard(
            appName: app?.localizedName ?? "this app",
            appIcon: app?.icon,
            modeName: modeName,
            bindings: bindings,
            onClose: { [weak self] in self?.hide() },
            onMute: onMute.map { mute in { [weak self] in mute(); self?.hide() } },
            onHoverChange: { [weak self] inside in self?.hoverChanged(inside) }
        )
        let host = NSHostingView(rootView: card)
        panel.contentView = host

        // Room for the card plus the hover preview to its left.
        let rows = max(1, bindings.count)
        let size = NSSize(
            width: DiscoveryCard.cardWidth + DiscoveryCard.previewWidth + 34,
            height: min(640, 130 + Double(rows) * 44 + 40)
        )
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.maxX - size.width - 4, y: frame.maxY - size.height - 4,
                                  width: size.width, height: size.height), display: true)
        }

        isHovered = false
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func hoverChanged(_ inside: Bool) {
        isHovered = inside
        if inside {
            hideTask?.cancel()
        } else {
            scheduleHide()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !isHovered else { return }
        let task = DispatchWorkItem { [weak self] in self?.hide() }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: task)
    }

    private func makePanel() -> NSPanel {
        let panel = HUDPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

/// Lets the card's buttons work without ever making the panel key.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
