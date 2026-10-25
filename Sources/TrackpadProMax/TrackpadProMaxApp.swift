import SwiftUI
import TrackpadCore

@main
struct TrackpadProMaxApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            if let remaining = model.timerRemaining {
                // A running timer shows its countdown in the menu bar.
                Label(TimerKnobView.clock(remaining), systemImage: "timer")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            } else {
                Image(systemName: model.configuration.isEnabled ? model.activeMode.symbol : "hand.raised.slash")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Pressure Visualizer", id: WindowID.visualizer) {
            VisualizerView()
                .environment(model)
        }
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum WindowID {
    static let visualizer = "visualizer"
}
