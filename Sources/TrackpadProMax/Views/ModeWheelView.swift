import SwiftUI
import TrackpadCore

/// Radial mode picker, opened with a four-finger double tap. The knob in the
/// middle follows the finger; the pointed mode glows; a tap switches to it.
struct ModeWheelView: View {
    let state: OverlayState

    static let diameter = 380.0
    private var radius: Double { Self.diameter / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)

            ForEach(Array(state.wheelItems.enumerated()), id: \.element.id) { index, item in
                let highlighted = state.wheelHighlighted == index
                Wedge(index: index, count: state.wheelItems.count, inner: radius * 0.42, outer: radius - 6)
                    .fill(highlighted ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.04))
                    .shadow(color: highlighted ? .accentColor.opacity(0.9) : .clear, radius: 14)
                Wedge(index: index, count: state.wheelItems.count, inner: radius * 0.42, outer: radius - 6)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
                label(for: item, index: index, highlighted: highlighted)
            }

            center
            knob
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(30)
        .animation(.easeOut(duration: 0.12), value: state.wheelHighlighted)
    }

    private func label(for item: WheelItem, index: Int, highlighted: Bool) -> some View {
        let angle = RadialSelector.angle(of: index, count: state.wheelItems.count)
        let distance = radius * 0.71
        return VStack(spacing: 4) {
            Image(systemName: item.symbol)
                .font(.system(size: highlighted ? 30 : 24, weight: .semibold))
            Text(item.name)
                .font(.system(size: 13, weight: highlighted ? .bold : .medium))
                .lineLimit(1)
            if item.target == .gestureFolder {
                Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold)).opacity(0.7)
            }
            if state.wheelActive == index {
                Circle().frame(width: 5, height: 5)
            }
        }
        .foregroundStyle(highlighted ? .white : .primary)
        .frame(width: 110)
        .offset(x: sin(angle) * distance, y: -cos(angle) * distance)
    }

    private var center: some View {
        VStack(spacing: 3) {
            if state.wheelIsSubmenu {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            Text(state.wheelTitle)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: radius * 0.8, height: radius * 0.8)
        .background(Circle().fill(.regularMaterial))
    }

    private var subtitle: String {
        if let index = state.wheelHighlighted, state.wheelItems.indices.contains(index) {
            "Tap for \(state.wheelItems[index].name)"
        } else if state.wheelIsSubmenu {
            "Slide to pick · tap to go back"
        } else {
            "Slide to pick · tap to cancel"
        }
    }

    private var knob: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 14, height: 14)
            .shadow(color: .accentColor, radius: 6)
            .offset(x: state.wheelKnob.x * radius * 0.36, y: -state.wheelKnob.y * radius * 0.36)
    }
}

/// Ring segment centered on item `index`, 12 o'clock first, clockwise.
struct Wedge: Shape {
    let index: Int
    let count: Int
    let inner: Double
    let outer: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let span = 360.0 / Double(count)
        let mid = Double(index) * span - 90
        let gap = count > 1 ? 1.5 : 0
        let start = Angle.degrees(mid - span / 2 + gap), end = Angle.degrees(mid + span / 2 - gap)
        var path = Path()
        path.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
