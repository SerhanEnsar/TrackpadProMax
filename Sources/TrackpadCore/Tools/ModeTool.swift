import Foundation

/// Full-trackpad tools that live on the mode wheel next to surfaces.
public enum ModeTool: String, Sendable, Codable, CaseIterable {
    case windowTiling
    case appLauncher
    case quickSettings

    public var defaultName: String {
        switch self {
        case .windowTiling: "Windows"
        case .appLauncher: "Apps"
        case .quickSettings: "Quick Settings"
        }
    }

    public var symbol: String {
        switch self {
        case .windowTiling: "rectangle.split.2x2"
        case .appLauncher: "square.grid.3x3.fill"
        case .quickSettings: "switch.2"
        }
    }

    public var summary: String {
        switch self {
        case .windowTiling: "Split the screen into 2, 3 or 4 windows: pick a layout, drag the dividers, then drag apps into place."
        case .appLauncher: "Your favourite apps on a wheel: slide to pick, tap to open."
        case .quickSettings: "Toggle Dark Mode, Night Shift, Wi-Fi, Bluetooth, Keep Awake or lock the screen."
        }
    }

    public var defaultMode: Mode { Mode(name: defaultName, symbol: symbol, tool: self) }
}

/// One slot on the mode wheel.
public struct WheelItem: Identifiable, Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        /// Opens the sub-wheel of gesture modes.
        case gestureFolder
        case mode(UUID)
    }

    public var id: String
    public var name: String
    public var symbol: String
    public var target: Target

    public init(id: String, name: String, symbol: String, target: Target) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.target = target
    }
}

/// Builds the two levels of the mode wheel.
public enum WheelMenu {
    public static let folderName = "Normal"

    /// Normal (a folder of gesture modes) followed by every surface and tool.
    public static func main(_ configuration: Configuration) -> [WheelItem] {
        var items: [WheelItem] = []
        if !configuration.gestureModes.isEmpty {
            items.append(WheelItem(id: "folder.gestures", name: folderName, symbol: "hand.point.up.left", target: .gestureFolder))
        }
        items += configuration.modes.filter(\.isOverlay).map(item)
        return items
    }

    /// The gesture modes inside the Normal folder.
    public static func gestures(_ configuration: Configuration) -> [WheelItem] {
        configuration.gestureModes.map(item)
    }

    private static func item(_ mode: Mode) -> WheelItem {
        WheelItem(id: mode.id.uuidString, name: mode.name, symbol: mode.symbol, target: .mode(mode.id))
    }
}
