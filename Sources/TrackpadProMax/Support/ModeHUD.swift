import AppKit
import SwiftUI

/// Small translucent badge near the top of the screen that confirms a mode change.
@MainActor
final class ModeHUD {
    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?

    func show(name: String, symbol: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: ModeBadge(name: name, symbol: symbol))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 200, height: 48))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 24
            ))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }

        hideTask?.cancel()
        let task = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel?.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { panel?.orderOut(nil) }
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

private struct ModeBadge: View {
    let name: String
    let symbol: String

    var body: some View {
        Label(name, systemImage: symbol)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(8)
    }
}
