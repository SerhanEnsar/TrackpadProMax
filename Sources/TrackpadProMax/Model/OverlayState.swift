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

    struct TilingState {
        var phase = TilingFlow.Phase.chooseCount
        var quadrant: Int?
        var layout = TilingLayout(count: 2)
        var hoveredDivider: TilingLayout.Divider?
        var grabbedDivider: TilingLayout.Divider?
        var apps: [WindowTiler.App] = []
        var highlightedApp = 0
        var draggingApp: Int?
        /// Dragged icon position in layout coordinates (y down).
        var dragPoint: Point?
        var hoveredPane: Int?
        /// pane → app index
        var assignments: [Int: Int] = [:]
    }

    /// The window-tiling tool, while open.
    var tiling: TilingState?

    /// Shown in the middle of music surfaces.
    var nowPlaying: NowPlaying?
    /// Briefly set after a media tap/swipe for visual feedback.
    var mediaFeedback: (edge: SurfaceEdge, symbol: String)?
}
