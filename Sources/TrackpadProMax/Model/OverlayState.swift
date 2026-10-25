import Foundation
import Observation
import TrackpadCore

/// What the mode wheel and control surface overlays draw. Updated by
/// `InteractionController`, observed by the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    var wheelItems: [WheelItem] = []
    var wheelTitle = "TrackPadPM"
    /// The gesture-mode folder: its middle means Back instead of Cancel.
    var wheelIsSubmenu = false
    var wheelHighlighted: Int?
    var wheelKnob = Point(x: 0, y: 0)
    var wheelActive: Int?

    var surfaceName = ""
    var surfaceLayout = ControlSurfaceLayout()
    var surfaceValues: [SurfaceEdge: Double] = [:]
    var activeEdge: SurfaceEdge?
    struct DevicePickerState {
        var devices: [AudioOutputDevice]
        var highlighted: Int
        var volumes: [AudioOutputDevice.ID: Double]
    }

    /// Output-device bars, opened by a hard press on the volume bar.
    var devicePicker: DevicePickerState?

    /// Shown in the middle of music surfaces.
    var nowPlaying: NowPlaying?
    /// Briefly set after a media tap/swipe for visual feedback.
    var mediaFeedback: (edge: SurfaceEdge, symbol: String)?
}
