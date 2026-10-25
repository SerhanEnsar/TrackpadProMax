import SwiftUI
import TrackpadCore

/// Timer dial: circle a finger to set minutes, tap to start.
struct TimerKnobView: View {
    let state: OverlayState

    static let diameter = 380.0

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)

            // Minute ticks; every fifth is longer.
            ForEach(0..<60, id: \.self) { tick in
                Capsule()
                    .fill(.primary.opacity(tick % 5 == 0 ? 0.6 : 0.25))
                    .frame(width: tick % 5 == 0 ? 3 : 1.5, height: tick % 5 == 0 ? 14 : 8)
                    .offset(y: -Self.diameter / 2 + 22)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }

            // One full ring per hour.
            let minutes = Double(state.timerMinutes)
            Circle()
                .trim(from: 0, to: min(1, minutes / 60))
                .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Self.diameter - 80, height: Self.diameter - 80)
                .shadow(color: .accentColor.opacity(0.6), radius: 8)
            if minutes > 60 {
                Circle()
                    .trim(from: 0, to: min(1, (minutes - 60) / 60))
                    .stroke(Color.orange.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: Self.diameter - 120, height: Self.diameter - 120)
            }

            VStack(spacing: 4) {
                if let remaining = state.timerRemaining {
                    Text(Self.clock(remaining)).font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("left · press firmly to cancel").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(state.timerMinutes)").font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(state.timerMinutes == 1 ? "minute" : "minutes").font(.headline).foregroundStyle(.secondary)
                }
                Text("Circle to set · press firmly to start · tap the middle to go back")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(width: 180)
                    .padding(.top, 6)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(30)
        .animation(.easeOut(duration: 0.1), value: state.timerMinutes)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
