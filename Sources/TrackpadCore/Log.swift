import os

/// Unified logging. Stream with:
/// `log stream --level debug --predicate 'subsystem == "io.github.serhanensar.TrackpadProMax"'`
public enum Log {
    public static let touch = Logger(subsystem: "io.github.serhanensar.TrackpadProMax", category: "touch")
    public static let gesture = Logger(subsystem: "io.github.serhanensar.TrackpadProMax", category: "gesture")
    public static let action = Logger(subsystem: "io.github.serhanensar.TrackpadProMax", category: "action")
}
