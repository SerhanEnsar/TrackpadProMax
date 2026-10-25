import AppKit
import SwiftUI
import TrackpadCore

/// Window tiling tool: pick a split, drag the dividers, drag apps into panes.
/// Everything is driven from the trackpad; nothing here takes clicks.
struct TilingView: View {
    let state: OverlayState

    static let size = CGSize(width: 780, height: 520)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            if let tiling = state.tiling {
                VStack(spacing: 16) {
                    header(tiling)
                    switch tiling.phase {
                    case .chooseCount: CountGrid(quadrant: tiling.quadrant)
                    case .adjust: LayoutPreview(tiling: tiling, showsApps: false)
                    case .assign:
                        HStack(spacing: 18) {
                            AppStrip(tiling: tiling)
                            LayoutPreview(tiling: tiling, showsApps: true)
                        }
                    }
                }
                .padding(26)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .padding(30)
        .animation(.easeOut(duration: 0.15), value: state.tiling?.phase)
    }

    private func header(_ tiling: OverlayState.TilingState) -> some View {
        VStack(spacing: 3) {
            Text(title(tiling.phase)).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(hint(tiling)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(_ phase: TilingFlow.Phase) -> String {
        switch phase {
        case .chooseCount: "Split the screen"
        case .adjust: "Adjust the split"
        case .assign: "Place your apps"
        }
    }

    private func hint(_ tiling: OverlayState.TilingState) -> String {
        switch tiling.phase {
        case .chooseCount: "Press a corner of the trackpad to choose"
        case .adjust: "Press near a line and drag it · two-finger tap to confirm"
        case .assign:
            "Slide on the left edge to pick an app · press and drag it onto a pane · \(tiling.assignments.count)/\(min(tiling.layout.count, tiling.apps.count)) placed"
        }
    }
}

// MARK: - Phase 1

private struct CountGrid: View {
    let quadrant: Int?

    var body: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow { cell(0); cell(1) }
            GridRow { cell(2); cell(3) }
        }
        .animation(.easeOut(duration: 0.12), value: quadrant)
    }

    private func cell(_ index: Int) -> some View {
        let highlighted = quadrant == index
        return VStack(spacing: 10) {
            if index == 0 {
                Image(systemName: "chevron.backward.circle.fill").font(.system(size: 40))
                Text("Back").font(.headline)
            } else {
                SplitIcon(count: index + 1).frame(width: 110, height: 70)
                Text("\(index + 1)").font(.system(size: 26, weight: .heavy, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(highlighted ? Color.accentColor.opacity(0.45) : .white.opacity(0.06))
        )
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(highlighted ? Color.accentColor : .white.opacity(0.12), lineWidth: highlighted ? 2 : 1))
        .shadow(color: highlighted ? .accentColor.opacity(0.8) : .clear, radius: 14)
        .scaleEffect(highlighted ? 1.03 : 1)
    }
}

/// Tiny picture of a split, used on the count grid.
private struct SplitIcon: View {
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let layout = TilingLayout(count: count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.panes.enumerated()), id: \.offset) { _, pane in
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.primary.opacity(0.8), lineWidth: 2)
                        .frame(width: pane.width * geo.size.width - 4, height: pane.height * geo.size.height - 4)
                        .offset(x: pane.x * geo.size.width + 2, y: pane.y * geo.size.height + 2)
                }
            }
        }
    }
}

// MARK: - Phases 2 and 3

private struct LayoutPreview: View {
    let tiling: OverlayState.TilingState
    let showsApps: Bool

    private var aspect: CGFloat {
        guard let frame = NSScreen.main?.visibleFrame, frame.height > 0 else { return 1.6 }
        return frame.width / frame.height
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiling.layout.panes.enumerated()), id: \.offset) { index, pane in
                    paneView(index: index)
                        .frame(width: pane.width * size.width - 6, height: pane.height * size.height - 6)
                        .offset(x: pane.x * size.width + 3, y: pane.y * size.height + 3)
                }
                ForEach(tiling.layout.dividers, id: \.self) { divider in
                    dividerLine(divider, in: size)
                }
                if showsApps, let app = tiling.draggingApp, let point = tiling.dragPoint, tiling.apps.indices.contains(app) {
                    Image(nsImage: tiling.apps[app].icon)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .shadow(radius: 8)
                        .position(x: point.x * size.width, y: point.y * size.height)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .animation(.interactiveSpring(response: 0.18), value: tiling.layout)
    }

    private func paneView(index: Int) -> some View {
        let hovered = tiling.hoveredPane == index
        let app = tiling.assignments[index].flatMap { tiling.apps.indices.contains($0) ? tiling.apps[$0] : nil }
        return ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 12).fill(hovered ? Color.accentColor.opacity(0.35) : .clear)
            if let app {
                VStack(spacing: 6) {
                    Image(nsImage: app.icon).resizable().frame(width: 52, height: 52)
                    Text(app.name).font(.caption.bold()).lineLimit(1)
                }
            } else {
                Text("\(index + 1)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovered ? Color.accentColor : .white.opacity(0.15), lineWidth: hovered ? 2 : 1))
    }

    private func dividerLine(_ divider: TilingLayout.Divider, in size: CGSize) -> some View {
        let (a, b) = tiling.layout.segment(divider)
        let grabbed = tiling.grabbedDivider == divider
        let hovered = tiling.hoveredDivider == divider
        return Path { path in
            path.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
            path.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
        }
        .stroke(grabbed || hovered ? Color.accentColor : .white.opacity(0.7),
                style: StrokeStyle(lineWidth: grabbed ? 6 : (hovered ? 4 : 2), lineCap: .round))
        .shadow(color: grabbed ? .accentColor : .clear, radius: 8)
        .opacity(showsApps ? 0.4 : 1)
    }
}

private struct AppStrip: View {
    let tiling: OverlayState.TilingState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(tiling.apps.enumerated()), id: \.element.id) { index, app in
                        row(app, index: index).id(index)
                    }
                }
                .padding(6)
            }
            .onChange(of: tiling.highlightedApp) { _, index in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.15)))
    }

    private func row(_ app: WindowTiler.App, index: Int) -> some View {
        let highlighted = tiling.highlightedApp == index
        let placed = tiling.assignments.values.contains(index)
        return VStack(spacing: 4) {
            Image(nsImage: app.icon).resizable().frame(width: 44, height: 44)
            Text(app.name).font(.caption2).lineLimit(1)
        }
        .frame(width: 104, height: 74)
        .background(RoundedRectangle(cornerRadius: 12).fill(highlighted ? Color.accentColor.opacity(0.45) : .clear))
        .shadow(color: highlighted ? .accentColor.opacity(0.8) : .clear, radius: 10)
        .opacity(tiling.draggingApp == index ? 0.35 : (placed ? 0.6 : 1))
        .overlay(alignment: .topTrailing) {
            if placed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).padding(4) }
        }
    }
}
