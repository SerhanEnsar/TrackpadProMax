import SwiftUI
import TrackpadCore

/// 3×3 grid mirrored on the trackpad: slide to highlight, tap to flip.
struct QuickSettingsView: View {
    let state: OverlayState

    static let size = CGSize(width: 560, height: 350)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            cell(row * 3 + column)
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(30)
        .animation(.easeOut(duration: 0.12), value: state.quickHighlighted)
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let highlighted = state.quickHighlighted == index
        let toggle = QuickToggle.grid[index]
        let on = toggle.flatMap { state.quickStates[$0] } ?? false
        VStack(spacing: 6) {
            if let toggle {
                Image(systemName: toggle.symbol).font(.system(size: 24, weight: .semibold))
                Text(toggle.name).font(.callout.weight(.semibold))
                Text(toggle.isMomentary ? "Tap" : (on ? "On" : "Off"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(on ? .white : .secondary)
            } else {
                Image(systemName: "chevron.backward.circle.fill").font(.system(size: 28))
                Text("Back").font(.callout.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(on ? Color.accentColor.opacity(0.75) : .white.opacity(0.06))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(highlighted ? Color.accentColor : .white.opacity(0.12), lineWidth: highlighted ? 2.5 : 1))
        .shadow(color: highlighted ? .accentColor.opacity(0.9) : .clear, radius: 12)
        .scaleEffect(highlighted ? 1.04 : 1)
    }
}
