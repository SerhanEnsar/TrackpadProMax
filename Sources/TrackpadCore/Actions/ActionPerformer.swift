import AppKit
import CoreGraphics
import Foundation

/// Executes `Action`s by synthesizing input events or launching helpers.
///
/// Posting keyboard/mouse events requires the Accessibility permission.
@MainActor
public final class ActionPerformer {
    public static let shared = ActionPerformer()

    /// Called for `.nextMode`; owned by the app layer.
    public var onNextMode: (() -> Void)?

    private init() {}

    public static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    public static func requestAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func perform(_ action: Action) {
        switch action {
        case let .keyboardShortcut(combo):
            postKey(combo)
        case let .mouseClick(button):
            click(button)
        case let .system(system):
            perform(system)
        case let .launchApp(path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        case let .openURL(string):
            if let url = URL(string: string) { NSWorkspace.shared.open(url) }
        case let .runShortcut(name):
            run("/usr/bin/shortcuts", ["run", name])
        case let .appleScript(source):
            runAppleScript(source)
        case .nextMode:
            onNextMode?()
        }
    }

    // MARK: - Keyboard & mouse

    private func postKey(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: combo.modifiers)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func click(_ button: MouseButton) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .center)
        }
        for type in [down, up] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton)?
                .post(tap: .cghidEventTap)
        }
    }

    // MARK: - System

    private func perform(_ action: SystemAction) {
        let missionControl = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"
        switch action {
        case .missionControl: run(missionControl, [])
        case .showDesktop: run(missionControl, ["1"])
        case .appWindows: run(missionControl, ["2"])
        case .screenshot: run("/usr/bin/open", ["-b", "com.apple.screenshot.launcher"])
        case .lockScreen: postKey(KeyCombo(keyCode: 12, modifiers: CGEventFlags([.maskControl, .maskCommand]).rawValue))
        case .playPause: postAuxKey(16)
        case .nextTrack: postAuxKey(17)
        case .previousTrack: postAuxKey(18)
        case .volumeUp: postAuxKey(0)
        case .volumeDown: postAuxKey(1)
        case .mute: postAuxKey(7)
        case .brightnessUp: postAuxKey(2)
        case .brightnessDown: postAuxKey(3)
        }
    }

    /// Media/brightness keys are `NSSystemDefined` events with an NX_KEYTYPE code.
    private func postAuxKey(_ keyType: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int((keyType << 16) | (state << 8)), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Helpers

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
