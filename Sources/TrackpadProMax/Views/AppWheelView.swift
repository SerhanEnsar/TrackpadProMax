import SwiftUI
import TrackpadCore

/// Launcher wheel: favourite apps around a ring, same feel as the mode wheel.
struct AppWheelView: View {
    let state: OverlayState

    static let diameter = 420.0
    private var radius: Double { Self.diameter / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)

            ForEach(Array(state.launcherApps.enumerated()), id: \.element.id) { index, app in
                let highlighted = state.launcherHighlighted == index
                let count = state.launcherApps.count
                Wedge(index: index, count: count, inner: radius * 0.4, outer: radius - 6)
                    .fill(highlighted ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.04))
                    .shadow(color: highlighted ? .accentColor.opacity(0.9) : .clear, radius: 14)
                let angle = RadialSelector.angle(of: index, count: count)
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: highlighted ? 64 : 48, height: highlighted ? 64 : 48)
                    .offset(x: sin(angle) * radius * 0.7, y: -cos(angle) * radius * 0.7)
            }

            VStack(spacing: 3) {
                Image(systemName: "chevron.backward").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                Text(highlightedName ?? "Apps").font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(highlightedName == nil ? "Slide to pick · tap to go back" : "Tap to open")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: radius * 0.78, height: radius * 0.78)
            .background(Circle().fill(.regularMaterial))

            Circle()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
                .shadow(color: .accentColor, radius: 6)
                .offset(x: state.launcherKnob.x * radius * 0.34, y: -state.launcherKnob.y * radius * 0.34)

            if state.launcherApps.isEmpty {
                Text("No apps yet — add some in Settings › Gestures › Apps").font(.callout).offset(y: radius + 20)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(30)
        .animation(.easeOut(duration: 0.12), value: state.launcherHighlighted)
    }

    private var highlightedName: String? {
        state.launcherHighlighted.flatMap { state.launcherApps.indices.contains($0) ? state.launcherApps[$0].name : nil }
    }
}
