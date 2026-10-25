import SwiftUI
import TrackpadCore

/// On-screen trackpad shown in a control surface mode. Each edge holds a bar
/// that mirrors the matching edge of the real trackpad.
struct ControlSurfaceView: View {
    let state: OverlayState

    static let size = CGSize(width: 560, height: 350)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)

            VStack(spacing: 4) {
                Text(state.surfaceName).font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Slide along an edge · 4-finger double tap for modes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            bar(.left).frame(width: 52, height: 230).offset(x: -Self.size.width / 2 + 48)
            bar(.right).frame(width: 52, height: 230).offset(x: Self.size.width / 2 - 48)
            bar(.top).frame(width: 340, height: 48).offset(y: -Self.size.height / 2 + 42)
            bar(.bottom).frame(width: 340, height: 48).offset(y: Self.size.height / 2 - 42)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(30)
        .animation(.easeOut(duration: 0.12), value: state.activeEdge)
    }

    @ViewBuilder
    private func bar(_ edge: SurfaceEdge) -> some View {
        let control = state.surfaceLayout[edge]
        let active = state.activeEdge == edge
        ZStack {
            Capsule().fill(.black.opacity(0.18))
            if control.isContinuous {
                fill(edge: edge, value: state.surfaceValues[edge] ?? 0)
            }
            content(edge: edge, control: control)
        }
        .overlay(Capsule().strokeBorder(active ? Color.accentColor : .white.opacity(0.15), lineWidth: active ? 2 : 1))
        .shadow(color: active ? .accentColor.opacity(0.7) : .clear, radius: 10)
        .scaleEffect(active ? 1.05 : 1)
        .opacity(control == .none ? 0.35 : 1)
    }

    private func fill(edge: SurfaceEdge, value: Double) -> some View {
        GeometryReader { geo in
            let v = min(1, max(0, value))
            if edge.isVertical {
                VStack {
                    Spacer(minLength: 0)
                    Capsule().fill(Color.accentColor.gradient).frame(height: max(geo.size.width, geo.size.height * v))
                }
                .opacity(v > 0 ? 1 : 0)
            } else {
                HStack {
                    Capsule().fill(Color.accentColor.gradient).frame(width: max(geo.size.height, geo.size.width * v))
                    Spacer(minLength: 0)
                }
                .opacity(v > 0 ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.08), value: value)
    }

    @ViewBuilder
    private func content(edge: SurfaceEdge, control: SurfaceControl) -> some View {
        let percent = Int(((state.surfaceValues[edge] ?? 0) * 100).rounded())
        switch control {
        case .media:
            let feedback = state.mediaFeedback?.edge == edge ? state.mediaFeedback?.symbol : nil
            let layout = edge.isVertical ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(spacing: 30))
            layout {
                ForEach(edge.isVertical ? ["forward.fill", "playpause.fill", "backward.fill"]
                                        : ["backward.fill", "playpause.fill", "forward.fill"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .scaleEffect(feedback == symbol ? 1.5 : 1)
                        .foregroundStyle(feedback == symbol ? Color.accentColor : .primary)
                }
            }
        case .none:
            Image(systemName: control.symbol).font(.system(size: 14))
        default:
            if edge.isVertical {
                VStack(spacing: 6) {
                    Image(systemName: control.symbol).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(percent)").font(.caption.monospacedDigit().bold())
                }
                .padding(.vertical, 12)
            } else {
                HStack {
                    Image(systemName: control.symbol).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(percent)").font(.caption.monospacedDigit().bold())
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
