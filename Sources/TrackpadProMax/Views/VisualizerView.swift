import SwiftUI
import TrackpadCore

/// Live view of every finger on the trackpad, its force, and recognized gestures.
/// Doubles as a calibration aid for the press thresholds.
struct VisualizerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.animation) { _ in
                    let frame = model.pipeline.latestFrame
                    VStack(spacing: 14) {
                        TrackpadCanvas(frame: frame, settings: model.configuration.gestures)
                            .aspectRatio(1.6, contentMode: .fit)
                        ForceMeter(force: frame.activeTouches.map(\.pressure).max() ?? 0,
                                   settings: model.configuration.gestures)
                        FingerTable(touches: frame.activeTouches)
                    }
                }
            }
            .frame(minWidth: 420)

            GestureLog(gestures: model.recentGestures)
                .frame(width: 220)
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .overlay {
            if !model.isMultitouchAvailable {
                ContentUnavailableView(
                    "No multitouch data",
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text("MultitouchSupport could not be loaded on this system.")
                )
                .background(.background)
            }
        }
    }
}

private struct TrackpadCanvas: View {
    let frame: TouchFrame
    let settings: GestureSettings

    var body: some View {
        Canvas { context, size in
            let surface = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let shape = RoundedRectangle(cornerRadius: 14).path(in: surface)
            context.fill(shape, with: .color(.secondary.opacity(0.08)))
            context.stroke(shape, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

            // Edge/corner zone guides.
            let mx = surface.width * settings.zoneMargin, my = surface.height * settings.zoneMargin
            var guides = Path()
            for x in [surface.minX + mx, surface.maxX - mx] {
                guides.move(to: CGPoint(x: x, y: surface.minY))
                guides.addLine(to: CGPoint(x: x, y: surface.maxY))
            }
            for y in [surface.minY + my, surface.maxY - my] {
                guides.move(to: CGPoint(x: surface.minX, y: y))
                guides.addLine(to: CGPoint(x: surface.maxX, y: y))
            }
            context.stroke(guides, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            for touch in frame.touches where touch.phase.isDown {
                let center = CGPoint(
                    x: surface.minX + touch.position.x * surface.width,
                    y: surface.maxY - touch.position.y * surface.height
                )
                let tier = settings.tier(forForce: touch.pressure)
                let color = TierStyle.color(tier)
                let radius = max(14, min(48, touch.size * 18))
                let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(disc, with: .color(color.opacity(0.35)))
                context.stroke(disc, with: .color(color), lineWidth: 2)

                // Ring grows with force, full ring = hard threshold.
                let progress = min(1, touch.pressure / settings.hardThreshold)
                var ring = Path()
                ring.addArc(center: center, radius: radius + 6, startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                context.stroke(ring, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                context.draw(Text("\(Int(touch.pressure))").font(.caption.monospacedDigit().bold()), at: center)
            }
        }
    }
}

private struct ForceMeter: View {
    let force: Double
    let settings: GestureSettings

    var body: some View {
        let scale = settings.hardThreshold * 1.3
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Force").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(settings.tier(forForce: force)?.displayName ?? "Resting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TierStyle.color(settings.tier(forForce: force)))
                Text("\(Int(force))").font(.caption.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule()
                        .fill(TierStyle.color(settings.tier(forForce: force)))
                        .frame(width: geo.size.width * min(1, force / scale))
                    ForEach(PressTier.allCases, id: \.self) { tier in
                        Rectangle()
                            .fill(TierStyle.color(tier))
                            .frame(width: 2)
                            .offset(x: geo.size.width * settings.threshold(for: tier) / scale)
                    }
                }
            }
            .frame(height: 10)
        }
    }
}

private struct FingerTable: View {
    let touches: [Touch]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 3) {
            GridRow {
                Text("Finger"); Text("X"); Text("Y"); Text("Force"); Text("Size"); Text("Angle")
            }
            .foregroundStyle(.secondary)
            ForEach(touches, id: \.id) { touch in
                GridRow {
                    Text("#\(touch.id)")
                    Text(touch.position.x, format: .number.precision(.fractionLength(2)))
                    Text(touch.position.y, format: .number.precision(.fractionLength(2)))
                    Text(touch.pressure, format: .number.precision(.fractionLength(0)))
                    Text(touch.size, format: .number.precision(.fractionLength(2)))
                    Text(touch.angle, format: .number.precision(.fractionLength(2)))
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
    }
}

private struct GestureLog: View {
    let gestures: [AppModel.FiredGesture]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recognized gestures").font(.headline)
            if gestures.isEmpty {
                Text("Tap or press the trackpad. Gestures appear here with the action they triggered.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(gestures) { gesture in
                VStack(alignment: .leading, spacing: 1) {
                    Text(gesture.trigger.displayName).font(.callout)
                    if let action = gesture.actionName {
                        Text("→ \(action)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }
}

enum TierStyle {
    static func color(_ tier: PressTier?) -> Color {
        switch tier {
        case nil: .accentColor
        case .light: .green
        case .medium: .orange
        case .hard: .red
        }
    }
}
