import Foundation

/// A grid laid over the whole trackpad: the cell under the finger is
/// highlighted, a tap picks it. Cells are numbered row by row from the top.
public struct GridPicker: Sendable {
    public enum Event: Sendable, Equatable {
        case highlight(Int?)
        case tap(Int)
    }

    public let columns: Int
    public let rows: Int
    public private(set) var highlighted: Int?
    public var maxTapDuration: TimeInterval = 0.3
    public var maxTapMovement = 0.04

    private var trackedID: Int?
    private var start = Point(x: 0, y: 0)
    private var startTime: TimeInterval = 0
    private var movement = 0.0
    private var multiFinger = false

    public init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
    }

    public func cell(at p: Point) -> Int {
        let column = min(columns - 1, max(0, Int(p.x * Double(columns))))
        let row = min(rows - 1, max(0, Int((1 - p.y) * Double(rows))))
        return row * columns + column
    }

    public mutating func process(_ frame: TouchFrame) -> [Event] {
        let active = frame.activeTouches
        if multiFinger {
            if active.isEmpty { multiFinger = false }
            return []
        }
        if active.count > 1 {
            multiFinger = true
            trackedID = nil
            return []
        }
        guard let touch = active.first else {
            guard trackedID != nil else { return [] }
            trackedID = nil
            let isTap = frame.timestamp - startTime <= maxTapDuration && movement <= maxTapMovement
            return isTap ? [.tap(cell(at: start))] : []
        }
        if touch.id != trackedID {
            trackedID = touch.id
            start = touch.position
            startTime = frame.timestamp
            movement = 0
        }
        movement = max(movement, start.distance(to: touch.position))
        let current = cell(at: touch.position)
        guard current != highlighted else { return [] }
        highlighted = current
        return [.highlight(current)]
    }
}

/// The switches on the Quick Settings grid (3×3, Back in the middle).
public enum QuickToggle: String, Sendable, CaseIterable {
    case darkMode, nightShift, keepAwake
    case wifi, bluetooth
    case mute, micMute, lockScreen

    /// Grid cell → toggle; nil is the Back cell in the middle.
    public static let grid: [QuickToggle?] = [
        .darkMode, .nightShift, .keepAwake,
        .wifi, nil, .bluetooth,
        .mute, .micMute, .lockScreen,
    ]

    public var name: String {
        switch self {
        case .darkMode: "Dark Mode"
        case .nightShift: "Night Shift"
        case .keepAwake: "Keep Awake"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .mute: "Mute"
        case .micMute: "Mic Off"
        case .lockScreen: "Lock Screen"
        }
    }

    public var symbol: String {
        switch self {
        case .darkMode: "circle.lefthalf.filled"
        case .nightShift: "sun.horizon.fill"
        case .keepAwake: "cup.and.saucer.fill"
        case .wifi: "wifi"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .mute: "speaker.slash.fill"
        case .micMute: "mic.slash.fill"
        case .lockScreen: "lock.fill"
        }
    }

    /// Actions rather than on/off switches.
    public var isMomentary: Bool { self == .lockScreen }
}
