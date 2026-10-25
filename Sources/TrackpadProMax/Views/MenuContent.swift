import SwiftUI
import TrackpadCore

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TrackpadProMax").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $model.configuration.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            if !model.hasAccessibility {
                PermissionBanner()
            }
            if !model.isMultitouchAvailable {
                Label("Multitouch data is unavailable on this Mac.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode").font(.caption).foregroundStyle(.secondary)
                Picker("Mode", selection: Binding(
                    get: { model.configuration.activeModeID },
                    set: { model.selectMode($0) }
                )) {
                    ForEach(model.configuration.modes) { mode in
                        Label(mode.name, systemImage: mode.symbol).tag(mode.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let hotkey = model.configuration.modeHotkey {
                    Text("Mode wheel: 4-finger double tap or \(KeyNames.describe(hotkey))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ActiveBindingsList()

            Divider()

            HStack {
                Button("Visualizer", systemImage: "waveform.path.ecg") {
                    open { openWindow(id: WindowID.visualizer) }
                }
                Button("Settings…", systemImage: "gearshape") {
                    open { openSettings() }
                }
                Spacer()
                Menu {
                    ForEach(HapticPattern.allCases, id: \.self) { pattern in
                        Button(pattern.displayName) { HapticEngine.shared.play(pattern) }
                    }
                } label: {
                    Image(systemName: "waveform")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Test haptic feedback")
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                    .labelStyle(.iconOnly)
                    .help("Quit TrackpadProMax")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }

    /// Menu bar apps must activate before their windows come to the front.
    private func open(_ action: () -> Void) {
        NSApp.activate()
        action()
    }
}

private struct ActiveBindingsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bundleID = model.frontmostApp?.bundleIdentifier
        let bindings = model.activeMode.effectiveBindings(for: bundleID)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.frontmostApp?.localizedName.map { "Gestures in \($0)" } ?? "Gestures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show card", systemImage: "rectangle.on.rectangle") { model.showDiscoveryCard() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show the gesture card for this app")
            }
            if model.activeMode.isControlSurface {
                Text("Surface mode: slide along the trackpad's edges.").font(.callout).foregroundStyle(.secondary)
            } else if bindings.isEmpty {
                Text("No gestures in this mode.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(bindings) { binding in
                HStack(alignment: .firstTextBaseline) {
                    Text(binding.trigger.displayName)
                    Spacer(minLength: 8)
                    Text(binding.action.displayName).foregroundStyle(.secondary)
                }
                .font(.callout)
                .lineLimit(1)
            }
        }
    }
}

struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
            Text("Gestures can be detected, but actions like shortcuts and clicks need permission to control your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Grant Access…") { model.requestAccessibility() }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
