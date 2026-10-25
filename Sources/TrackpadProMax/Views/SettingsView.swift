import SwiftUI
import TrackpadCore

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Gestures", systemImage: "hand.tap") { BindingsSettings() }
            Tab("Sensitivity", systemImage: "slider.horizontal.3") { SensitivitySettings() }
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .frame(width: 640, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.hasAccessibility {
                Section { PermissionBanner() }
            }
            Section("Behavior") {
                Toggle("Enable TrackpadProMax", isOn: $model.configuration.isEnabled)
                Toggle("Haptic confirmation when a gesture fires", isOn: $model.configuration.hapticOnTrigger)
                Picker("Confirmation pattern", selection: $model.configuration.triggerHaptic) {
                    ForEach(HapticPattern.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(!model.configuration.hapticOnTrigger)
            }
            Section("Mode switching") {
                LabeledContent("Next mode shortcut") {
                    ShortcutRecorder(combo: $model.configuration.modeHotkey)
                }
            }
            Section("Haptics") {
                LabeledContent("Engine") {
                    Text(HapticEngine.shared.usesPrivateActuator ? "Direct actuator" : "System feedback (fallback)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    ForEach(HapticPattern.allCases, id: \.self) { pattern in
                        Button(pattern.displayName) { HapticEngine.shared.play(pattern) }
                    }
                }
                .controlSize(.small)
            }
            Section {
                if let error = model.saveError {
                    Label("Could not save settings: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                LabeledContent("Settings file") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.url])
                    }
                }
                Button("Reset all settings to defaults…", role: .destructive) { model.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sensitivity

private struct SensitivitySettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ThresholdSlider(title: "Light press", value: $model.configuration.gestures.lightThreshold, range: 20...300)
                ThresholdSlider(title: "Medium press", value: $model.configuration.gestures.mediumThreshold, range: 80...600)
                ThresholdSlider(title: "Hard press", value: $model.configuration.gestures.hardThreshold, range: 150...1000)
            } header: {
                Text("Force thresholds")
            } footer: {
                HStack {
                    Text("Press the trackpad in the visualizer to see your own force values.")
                    Spacer()
                    Button("Open Visualizer") { NSApp.activate(); openWindow(id: WindowID.visualizer) }
                }
            }
            Section("Taps") {
                LabeledContent("Max tap duration") {
                    Slider(value: $model.configuration.gestures.maxTapDuration, in: 0.1...0.5)
                    Text("\(Int(model.configuration.gestures.maxTapDuration * 1000)) ms").monospacedDigit().frame(width: 60)
                }
                LabeledContent("Double tap interval") {
                    Slider(value: $model.configuration.gestures.doubleTapInterval, in: 0.15...0.6)
                    Text("\(Int(model.configuration.gestures.doubleTapInterval * 1000)) ms").monospacedDigit().frame(width: 60)
                }
            }
            Section("Zones") {
                LabeledContent("Edge & corner size") {
                    Slider(value: $model.configuration.gestures.zoneMargin, in: 0.08...0.33)
                    Text("\(Int(model.configuration.gestures.zoneMargin * 100)) %").monospacedDigit().frame(width: 60)
                }
            }
            Section {
                Button("Restore default sensitivity") { model.configuration.gestures = GestureSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThresholdSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            Slider(value: $value, in: range, step: 5)
            Text("\(Int(value))").monospacedDigit().frame(width: 60)
        }
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.point.up.left.and.text")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("TrackpadProMax").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Pressure-sensitive gestures and haptic feedback for the Force Touch trackpad.")
                .multilineTextAlignment(.center)
            Link("github.com/SerhanEnsar/TrackpadProMax", destination: URL(string: "https://github.com/SerhanEnsar/TrackpadProMax")!)
            Text("Open source under the Apache License 2.0.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
