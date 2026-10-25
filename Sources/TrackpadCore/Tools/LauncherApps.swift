import Foundation

/// Apps shown on the launcher wheel.
public enum LauncherApps {
    public static let maxCount = 10

    /// Bundle IDs of the apps kept in the Dock, in Dock order.
    public static func dockApps() -> [String] {
        let tiles = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let ids = tiles.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
        return Array(ids.prefix(maxCount))
    }

    /// The user's list, or the Dock's apps until they make one.
    public static func resolve(_ configured: [String]) -> [String] {
        configured.isEmpty ? dockApps() : Array(configured.prefix(maxCount))
    }
}
