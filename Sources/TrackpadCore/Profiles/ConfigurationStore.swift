import Foundation

/// Loads and saves `Configuration` as JSON in Application Support.
public struct ConfigurationStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrackpadProMax", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Returns defaults if the file is missing; keeps a backup of an unreadable file
    /// instead of silently overwriting the user's settings.
    public func load() -> Configuration {
        guard let data = try? Data(contentsOf: url) else { return .defaults }
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return .defaults
        }
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
