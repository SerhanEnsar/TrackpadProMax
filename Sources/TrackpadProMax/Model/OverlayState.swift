import Foundation
import Observation
import TrackpadCore

/// What the mode wheel and control surface overlays draw. Updated by
/// `InteractionController`, observed by the SwiftUI views.
@MainActor
@Observable
final class OverlayState {
    struct WheelItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let symbol: String
    }

    var wheelItems: [WheelItem] = []
    var wheelHighlighted: Int?
    var wheelKnob = Point(x: 0, y: 0)
    var wheelActive: Int?

    var surfaceName = ""
    var surfaceLayout = ControlSurfaceLayout()
    var surfaceValues: [SurfaceEdge: Double] = [:]
    var activeEdge: SurfaceEdge?
    /// Shown in the middle of music surfaces.
    var nowPlaying: NowPlaying?
    /// Briefly set after a media tap/swipe for visual feedback.
    var mediaFeedback: (edge: SurfaceEdge, symbol: String)?
}
