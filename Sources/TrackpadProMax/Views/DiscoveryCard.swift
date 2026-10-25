import AppKit
import SwiftUI
import TrackpadCore

/// Notification-style card listing the gestures available in an app. Hovering
/// a row plays that gesture on a small animated trackpad beside the card.
struct DiscoveryCard: View {
    let appName: String
    let appIcon: NSImage?
    let modeName: String
    let bindings: [GestureBinding]
    let onClose: () -> Void
    let onMute: (() -> Void)?
    let onHoverChange: (Bool) -> Void

    @State private var hovered: GestureBinding?

    static let cardWidth = 300.0
    static let previewWidth = 190.0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            preview
                .frame(width: Self.previewWidth)
            card
                .frame(width: Self.cardWidth)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    @ViewBuilder private var preview: some View {
        if let hovered {
            VStack(spacing: 8) {
                GestureAnimationView(trigger: hovered.trigger)
                    .id(hovered.id)
                Text(hovered.trigger.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "rectangle.and.hand.point.up.left.filled")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .offset(x: 4, y: 4)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trackpad gestures in \(appName)").font(.headline).lineLimit(1)
                    Text("\(modeName) mode · hover to preview").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close")
            }

            if bindings.isEmpty {
                Text("No gestures in this app yet. Add some in TrackpadProMax Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(bindings) { binding in
                    row(binding)
                }
            }

            if let onMute {
                Button("Don't show for \(appName)", action: onMute)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .onHover(perform: onHoverChange)
    }

    private func row(_ binding: GestureBinding) -> some View {
        HStack(spacing: 8) {
            Image(systemName: binding.trigger.symbol)
                .frame(width: 20)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(binding.action.displayName).font(.callout.weight(.medium)).lineLimit(1)
                Text(binding.trigger.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered?.id == binding.id ? Color.accentColor.opacity(0.15) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside {
                    hovered = binding
                } else if hovered?.id == binding.id {
                    hovered = nil
                }
            }
        }
    }
}
