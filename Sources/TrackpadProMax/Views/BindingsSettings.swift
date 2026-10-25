import AppKit
import SwiftUI
import TrackpadCore

/// Edits the bindings of a mode, either for all apps or for one app.
struct BindingsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var modeID: UUID?
    /// `nil` = bindings for all apps.
    @State private var appBundleID: String?
    @State private var editing: GestureBinding?
    @State private var isNew = false
    @State private var renamingMode = false
    @State private var modeName = ""

    var body: some View {
        @Bindable var model = model
        let modeIndex = currentModeIndex
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Mode", selection: Binding(get: { model.configuration.modes[modeIndex].id }, set: { modeID = $0 })) {
                    ForEach(model.configuration.modes) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                }
                .frame(maxWidth: 220)
                Menu {
                    Button("Rename…") {
                        modeName = model.configuration.modes[modeIndex].name
                        renamingMode = true
                    }
                    Menu("Icon") {
                        ForEach(Self.modeSymbols, id: \.self) { symbol in
                            Button { model.configuration.modes[modeIndex].symbol = symbol } label: { Image(systemName: symbol) }
                        }
                    }
                    Divider()
                    Button("New Gesture Mode") { addMode() }
                    Button("New Surface Mode") { addMode(surface: true) }
                    Button("Duplicate Mode") { duplicateMode(modeIndex) }
                    Button("Delete Mode", role: .destructive) { deleteMode(modeIndex) }
                        .disabled(model.configuration.modes.count < 2)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                if !isSurface(modeIndex) {
                    Picker("Apps", selection: $appBundleID) {
                        Text("All Apps").tag(String?.none)
                        ForEach(model.configuration.modes[modeIndex].appProfiles) { profile in
                            Text(profile.appName).tag(Optional(profile.bundleID))
                        }
                    }
                    .frame(maxWidth: 220)
                    Button("Add App…", systemImage: "plus.app") { addApp(modeIndex) }
                        .labelStyle(.iconOnly)
                        .help("Add gestures that only apply in one app")
                }
            }

            if let tool = model.configuration.modes[modeIndex].tool {
                VStack(alignment: .leading, spacing: 12) {
                    Label(tool.defaultName, systemImage: tool.symbol).font(.title3.bold())
                    Text(tool.summary).foregroundStyle(.secondary)
                    Text("Open it from the mode wheel (four-finger double tap). A four-finger tap or Esc closes it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if isSurface(modeIndex) {
                SurfaceLayoutEditor(layout: Binding(
                    get: { model.configuration.modes[modeIndex].surface ?? ControlSurfaceLayout() },
                    set: { model.configuration.modes[modeIndex].surface = $0 }
                ))
            } else {
                bindingList(modeIndex)
            }
        }
        .padding(20)
        .sheet(item: $editing) { binding in
            BindingEditor(binding: binding, isNew: isNew) { saved in
                save(modeIndex, saved)
            }
        }
        .alert("Rename Mode", isPresented: $renamingMode) {
            TextField("Name", text: $modeName)
            Button("Rename") {
                let name = modeName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { model.configuration.modes[modeIndex].name = name }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: modeID) { appBundleID = nil }
    }

    /// Surfaces and tools have no per-app gesture lists.
    private func isSurface(_ modeIndex: Int) -> Bool {
        model.configuration.modes[modeIndex].isOverlay
    }

    @ViewBuilder
    private func bindingList(_ modeIndex: Int) -> some View {
            List {
                ForEach(bindings(modeIndex)) { binding in
                    BindingRow(binding: binding, isOn: Binding(
                        get: { binding.isEnabled },
                        set: { value in update(modeIndex, binding.id) { $0.isEnabled = value } }
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { edit(binding) }
                    .contextMenu {
                        Button("Edit…") { edit(binding) }
                        Button("Delete", role: .destructive) { delete(modeIndex, binding.id) }
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if bindings(modeIndex).isEmpty {
                    Text("No gestures yet. Click + to add one.").foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Add Gesture", systemImage: "plus") {
                    isNew = true
                    editing = GestureBinding(trigger: .tap(fingers: 3, count: 1, zone: .anywhere), action: .mouseClick(.middle))
                }
                if let appBundleID {
                    Button("Remove App Profile", role: .destructive) { removeApp(modeIndex, appBundleID) }
                }
                Spacer()
                Text("Double-click a gesture to edit it.").font(.caption).foregroundStyle(.secondary)
            }
    }

    static let modeSymbols = [
        "hand.point.up.left", "play.circle", "paintbrush.pointed", "keyboard", "gamecontroller",
        "film", "music.note", "terminal", "doc.richtext", "globe", "star", "bolt",
    ]

    private var currentModeIndex: Int {
        let modes = model.configuration.modes
        let id = modeID ?? model.configuration.activeModeID
        return modes.firstIndex { $0.id == id } ?? 0
    }

    private func bindings(_ modeIndex: Int) -> [GestureBinding] {
        let mode = model.configuration.modes[modeIndex]
        guard let appBundleID else { return mode.bindings }
        return mode.appProfiles.first { $0.bundleID == appBundleID }?.bindings ?? []
    }

    /// Applies `change` to the binding list currently shown.
    private func mutateBindings(_ modeIndex: Int, _ change: (inout [GestureBinding]) -> Void) {
        if let appBundleID,
           let appIndex = model.configuration.modes[modeIndex].appProfiles.firstIndex(where: { $0.bundleID == appBundleID }) {
            change(&model.configuration.modes[modeIndex].appProfiles[appIndex].bindings)
        } else {
            change(&model.configuration.modes[modeIndex].bindings)
        }
    }

    private func update(_ modeIndex: Int, _ id: UUID, _ change: (inout GestureBinding) -> Void) {
        mutateBindings(modeIndex) { list in
            if let index = list.firstIndex(where: { $0.id == id }) { change(&list[index]) }
        }
    }

    private func save(_ modeIndex: Int, _ binding: GestureBinding) {
        mutateBindings(modeIndex) { list in
            if let index = list.firstIndex(where: { $0.id == binding.id }) {
                list[index] = binding
            } else {
                list.append(binding)
            }
        }
    }

    private func delete(_ modeIndex: Int, _ id: UUID) {
        mutateBindings(modeIndex) { $0.removeAll { $0.id == id } }
    }

    private func edit(_ binding: GestureBinding) {
        isNew = false
        editing = binding
    }

    private func addMode(surface: Bool = false) {
        let mode = surface
            ? Mode(name: "Control \(model.configuration.modes.count + 1)",
                   symbol: "slider.horizontal.below.square.and.square.filled", surface: ControlSurfaceLayout())
            : Mode(name: "Mode \(model.configuration.modes.count + 1)", symbol: "star")
        model.configuration.modes.append(mode)
        modeID = mode.id
    }

    private func duplicateMode(_ index: Int) {
        var copy = model.configuration.modes[index]
        copy.id = UUID()
        copy.name += " Copy"
        model.configuration.modes.append(copy)
        modeID = copy.id
    }

    private func deleteMode(_ index: Int) {
        guard model.configuration.modes.count > 1 else { return }
        let removed = model.configuration.modes.remove(at: index)
        if model.configuration.activeModeID == removed.id {
            model.configuration.activeModeID = model.configuration.modes[0].id
        }
        modeID = nil
    }

    private func addApp(_ modeIndex: Int) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        if !model.configuration.modes[modeIndex].appProfiles.contains(where: { $0.bundleID == bundleID }) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            model.configuration.modes[modeIndex].appProfiles.append(AppProfile(bundleID: bundleID, appName: name))
        }
        appBundleID = bundleID
    }

    private func removeApp(_ modeIndex: Int, _ bundleID: String) {
        model.configuration.modes[modeIndex].appProfiles.removeAll { $0.bundleID == bundleID }
        appBundleID = nil
    }
}

private struct BindingRow: View {
    let binding: GestureBinding
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Toggle("", isOn: $isOn).labelsHidden()
            Image(systemName: binding.trigger.symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(binding.trigger.displayName)
            Spacer()
            Text(binding.action.displayName).foregroundStyle(.secondary)
        }
        .opacity(binding.isEnabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

extension Trigger {
    var symbol: String {
        switch self {
        case .tap: "hand.tap"
        case let .press(tier, _, _): tier == .hard ? "hand.point.up.braille.fill" : "hand.point.up.braille"
        }
    }
}

/// Picks the control on each edge of a control surface mode.
private struct SurfaceLayoutEditor: View {
    @Binding var layout: ControlSurfaceLayout

    var body: some View {
        VStack(spacing: 16) {
            Text("Slide along an edge of the trackpad to change its control; the middle picker sets what a tap in the middle does. Open it from the mode wheel; a four-finger tap, Esc or a few idle seconds close it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    picker(.top)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                GridRow {
                    picker(.left)
                    Picker("Middle", selection: $layout.center) {
                        ForEach(SurfaceCenter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .padding(10)
                    .frame(width: 190, height: 100)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.5)))
                    picker(.right)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    picker(.bottom)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(_ edge: SurfaceEdge) -> some View {
        Picker(edge.displayName, selection: $layout[edge]) {
            ForEach(SurfaceControl.allCases, id: \.self) { control in
                Label(control.displayName, systemImage: control.symbol).tag(control)
            }
        }
        .frame(width: 190)
    }
}
