import SwiftUI
import TrackpadCore

/// A small looping trackpad that acts out a trigger: fingers land, tap or
/// press down until the force ring reaches the tier, and the zone lights up.
struct GestureAnimationView: View {
    let trigger: Trigger

    /// Seconds per loop.
    static let period = 1.8

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
            Canvas { gc, size in
                draw(in: &gc, size: size, time: t)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityLabel(trigger.displayName)
    }

    // MARK: - Drawing

    private func draw(in gc: inout GraphicsContext, size: CGSize, time t: Double) {
        let pad = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
        let shape = RoundedRectangle(cornerRadius: size.height * 0.1).path(in: pad)
        gc.fill(shape, with: .color(.secondary.opacity(0.10)))
        gc.stroke(shape, with: .color(.secondary.opacity(0.45)), lineWidth: 1.5)

        if let zoneRect = zoneRect(in: pad) {
            let zone = RoundedRectangle(cornerRadius: size.height * 0.08).path(in: zoneRect.insetBy(dx: 3, dy: 3))
            gc.fill(zone, with: .color(.accentColor.opacity(0.22)))
            gc.stroke(zone, with: .color(.accentColor.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        let radius = size.height * 0.075
        let anchor = zoneCenter(in: pad)
        let points = fingerPoints(around: anchor, count: trigger.fingers, spacing: radius * 2.3)

        switch trigger {
        case let .tap(_, count, _):
            drawTaps(in: &gc, points: points, radius: radius, count: count, time: t)
        case let .press(tier, _, _):
            drawPress(in: &gc, points: points, radius: radius, tier: tier, time: t)
        }
    }

    private func drawTaps(in gc: inout GraphicsContext, points: [CGPoint], radius: Double, count: Int, time t: Double) {
        let starts = count == 2 ? [0.3, 0.62] : [0.4]
        for start in starts {
            let local = t - start
            guard local > -0.12, local < 0.42 else { continue }
            // Approach: grows from a hovering shadow into contact, then lifts away.
            let contact = local >= 0 && local < 0.14
            let approach = local < 0 ? 1 + (-local / 0.12) * 0.4 : 1
            let fade = local > 0.14 ? max(0, 1 - (local - 0.14) / 0.28) : 1
            for point in points {
                drawFinger(in: &gc, at: point, radius: radius * approach, opacity: fade, pressed: contact)
                if local >= 0 { drawRipple(in: &gc, at: point, radius: radius, progress: local / 0.42, color: .accentColor) }
            }
        }
    }

    private func drawPress(in gc: inout GraphicsContext, points: [CGPoint], radius: Double, tier: PressTier, time t: Double) {
        let level = Double(tier.rawValue) / Double(PressTier.allCases.count)
        let color = TierStyle.color(tier)
        // 0.15 land · 0.25–0.85 push · 0.85–1.15 hold (haptic) · 1.15–1.45 release
        guard t > 0.15, t < 1.45 else { return }
        let force: Double
        switch t {
        case ..<0.25: force = 0
        case ..<0.85: force = level * easeInOut((t - 0.25) / 0.6)
        case ..<1.15: force = level
        default: force = level * (1 - (t - 1.15) / 0.3)
        }
        let opacity = t > 1.25 ? max(0, 1 - (t - 1.25) / 0.2) : min(1, (t - 0.15) / 0.1)
        for point in points {
            drawFinger(in: &gc, at: point, radius: radius * (1 - force * 0.12), opacity: opacity, pressed: force > 0)
            // Force ring: a full circle equals a hard press.
            var ring = Path()
            ring.addArc(center: point, radius: radius * 1.45, startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * force), clockwise: false)
            gc.stroke(ring, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: radius * 0.32, lineCap: .round))
            // Haptic "thump" once the tier is reached.
            if t >= 0.85, t < 1.2 {
                drawRipple(in: &gc, at: point, radius: radius * 1.45, progress: (t - 0.85) / 0.35, color: color)
            }
        }
    }

    private func drawFinger(in gc: inout GraphicsContext, at p: CGPoint, radius: Double, opacity: Double, pressed: Bool) {
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        gc.fill(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity((pressed ? 0.55 : 0.25) * opacity)))
        gc.stroke(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(opacity)), lineWidth: 1.5)
    }

    private func drawRipple(in gc: inout GraphicsContext, at p: CGPoint, radius: Double, progress: Double, color: Color) {
        guard progress >= 0, progress <= 1 else { return }
        let r = radius * (1 + progress * 0.9)
        gc.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                  with: .color(color.opacity(0.6 * (1 - progress))), lineWidth: 1.5)
    }

    // MARK: - Geometry

    private static let margin = 0.32

    /// Highlighted area for the trigger's zone, in view coordinates (y down).
    private func zoneRect(in pad: CGRect) -> CGRect? {
        let w = pad.width * Self.margin, h = pad.height * Self.margin
        let (minX, midX, maxX) = (pad.minX, pad.minX + w, pad.maxX - w)
        let (top, midY, bottom) = (pad.minY, pad.minY + h, pad.maxY - h)
        switch trigger.zone {
        case .anywhere: return nil
        case .center: return CGRect(x: midX, y: midY, width: maxX - midX, height: bottom - midY)
        case .topLeft: return CGRect(x: minX, y: top, width: w, height: h)
        case .topRight: return CGRect(x: maxX, y: top, width: w, height: h)
        case .bottomLeft: return CGRect(x: minX, y: bottom, width: w, height: h)
        case .bottomRight: return CGRect(x: maxX, y: bottom, width: w, height: h)
        case .topEdge: return CGRect(x: midX, y: top, width: maxX - midX, height: h)
        case .bottomEdge: return CGRect(x: midX, y: bottom, width: maxX - midX, height: h)
        case .leftEdge: return CGRect(x: minX, y: midY, width: w, height: bottom - midY)
        case .rightEdge: return CGRect(x: maxX, y: midY, width: w, height: bottom - midY)
        }
    }

    private func zoneCenter(in pad: CGRect) -> CGPoint {
        guard let rect = zoneRect(in: pad), trigger.zone != .center else {
            return CGPoint(x: pad.midX, y: pad.midY)
        }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Fingers side by side in a gentle arc, like a real hand.
    private func fingerPoints(around c: CGPoint, count: Int, spacing: Double) -> [CGPoint] {
        let offsets = (0..<count).map { Double($0) - Double(count - 1) / 2 }
        return offsets.map { o in CGPoint(x: c.x + o * spacing, y: c.y + abs(o) * spacing * 0.25) }
    }

    private func easeInOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
