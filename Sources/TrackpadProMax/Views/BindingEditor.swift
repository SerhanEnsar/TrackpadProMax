import AppKit
import SwiftUI
import TrackpadCore

/// Sheet for creating or editing one gesture → action binding.
struct BindingEditor: View {
    let isNew: Bool
    let onSave: (GestureBinding) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GestureBinding
    @State private var trigger: TriggerDraft
    @State private var action: ActionDraft

    init(binding: GestureBinding, isNew: Bool, onSave: @escaping (GestureBinding) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: binding)
        _trigger = State(initialValue: TriggerDraft(binding.trigger))
        _action = State(initialValue: ActionDraft(binding.action))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("When I…") {
                    Picker("Gesture", selection: $trigger.kind) {
                        Text("Tap (no click)").tag(TriggerDraft.Kind.tap)
                        Text("Press with force").tag(TriggerDraft.Kind.press)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Fingers: \(trigger.fingers)", value: $trigger.fingers, in: 1...4)
                    if trigger.kind == .tap {
                        Picker("Taps", selection: $trigger.count) {
                            Text("Single").tag(1)
                            Text("Double").tag(2)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Force", selection: $trigger.tier) {
                            ForEach(PressTier.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Where", selection: $trigger.zone) {
                        ForEach(Zone.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if let warning = trigger.systemConflict {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("…do this") {
                    ActionFields(action: $action)
                }
            }
            .formStyle(.grouped)

            HStack {
                Text(trigger.make().displayName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    draft.trigger = trigger.make()
                    draft.action = action.make()
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!action.isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - Trigger draft

struct TriggerDraft {
    enum Kind: Hashable { case tap, press }
    var kind: Kind
    var fingers: Int
    var count = 1
    var tier: PressTier = .hard
    var zone: Zone

    init(_ trigger: Trigger) {
        switch trigger {
        case let .tap(fingers, count, zone):
            kind = .tap; self.fingers = fingers; self.count = count; self.zone = zone
        case let .press(tier, fingers, zone):
            kind = .press; self.fingers = fingers; self.tier = tier; self.zone = zone
        }
    }

    func make() -> Trigger {
        kind == .tap ? .tap(fingers: fingers, count: count, zone: zone) : .press(tier: tier, fingers: fingers, zone: zone)
    }

    /// Gestures that macOS already uses, so the user knows both will happen.
    var systemConflict: String? {
        switch (kind, fingers, count) {
        case (.tap, 1, _) where zone == .anywhere:
            "macOS also treats a one-finger tap as a click when Tap to Click is on."
        case (.tap, 2, 1) where zone == .anywhere:
            "macOS also treats a two-finger tap as a right click when Tap to Click is on."
        case (.tap, 2, 2):
            "Two-finger double tap is used by Smart Zoom in macOS."
        case (.press, 1, _) where tier == .light:
            "A light press fires on every normal click."
        case (.press, 1, _) where tier == .hard && zone == .anywhere:
            "Hard presses also trigger Force Click (Look Up) unless you turn it off in System Settings › Trackpad."
        default:
            nil
        }
    }
}

// MARK: - Action draft

struct ActionDraft {
    enum Kind: String, CaseIterable, Hashable {
        case shortcut = "Keyboard shortcut"
        case click = "Mouse click"
        case system = "System action"
        case app = "Open app"
        case url = "Open URL"
        case shortcutsApp = "Run Shortcut"
        case script = "AppleScript"
        case nextMode = "Next trackpad mode"
    }

    var kind: Kind
    var combo: KeyCombo?
    var button: MouseButton = .middle
    var system: SystemAction = .missionControl
    var appPath = ""
    var url = "https://"
    var shortcutName = ""
    var script = "display notification \"Hello from TrackpadProMax\""

    init(_ action: Action) {
        switch action {
        case let .keyboardShortcut(combo): kind = .shortcut; self.combo = combo
        case let .mouseClick(button): kind = .click; self.button = button
        case let .system(system): kind = .system; self.system = system
        case let .launchApp(path): kind = .app; appPath = path
        case let .openURL(url): kind = .url; self.url = url
        case let .runShortcut(name): kind = .shortcutsApp; shortcutName = name
        case let .appleScript(source): kind = .script; script = source
        case .nextMode: kind = .nextMode
        }
    }

    var isValid: Bool {
        switch kind {
        case .shortcut: combo != nil
        case .app: !appPath.isEmpty
        case .url: URL(string: url)?.scheme != nil && url.count > 8
        case .shortcutsApp: !shortcutName.trimmingCharacters(in: .whitespaces).isEmpty
        case .script: !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .click, .system, .nextMode: true
        }
    }

    func make() -> Action {
        switch kind {
        case .shortcut: .keyboardShortcut(combo ?? KeyCombo(keyCode: 0, modifiers: 0))
        case .click: .mouseClick(button)
        case .system: .system(system)
        case .app: .launchApp(path: appPath)
        case .url: .openURL(url)
        case .shortcutsApp: .runShortcut(name: shortcutName.trimmingCharacters(in: .whitespaces))
        case .script: .appleScript(source: script)
        case .nextMode: .nextMode
        }
    }
}

private struct ActionFields: View {
    @Binding var action: ActionDraft

    var body: some View {
        Picker("Action", selection: $action.kind) {
            ForEach(ActionDraft.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        switch action.kind {
        case .shortcut:
            LabeledContent("Shortcut") { ShortcutRecorder(combo: $action.combo, allowsClearing: false) }
        case .click:
            Picker("Button", selection: $action.button) {
                ForEach(MouseButton.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
        case .system:
            Picker("System action", selection: $action.system) {
                ForEach(SystemAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        case .app:
            LabeledContent("Application") {
                HStack {
                    Text(action.appPath.isEmpty ? "None" : FileManager.default.displayName(atPath: action.appPath))
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseApp() }
                }
            }
        case .url:
            TextField("URL", text: $action.url)
        case .shortcutsApp:
            TextField("Shortcut name", text: $action.shortcutName, prompt: Text("Exact name in the Shortcuts app"))
        case .script:
            TextEditor(text: $action.script)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
        case .nextMode:
            Text("Cycles to the next mode, same as the mode shortcut.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { action.appPath = url.path }
    }
}
