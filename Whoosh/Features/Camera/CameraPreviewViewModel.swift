import Foundation
import Observation

/// Holds everything the active ride screen needs to show the **live rear-camera
/// preview** with the experimental vision detections drawn on top (owner
/// device-testing feedback: "the user should be able to see the camera"). It is
/// a thin `@Observable`, main-actor view model: the `previewHost` is the same
/// seam Mount & frame uses (so the view never imports AVFoundation), and
/// `boxes` is the latest view-only `DetectionOverlayBox` set the detector
/// published.
///
/// ## What it is not
/// - It never captures, records, or uploads anything; footage and frames stay on
///   the device. The boxes are display-only and discarded as the next frame's
///   arrive — they are not the alert / near-miss path.
/// - It does not decide whether the preview is shown; the ride screen owns that
///   toggle (off by default to save battery). When the preview is hidden the
///   view simply stops drawing; boxes keep arriving only if an observer is set.
///
/// Honesty (privacy steering): the preview shows the road behind for the rider's
/// own records; detection is experimental and cannot guarantee detection or
/// delivery. The boxes are what the model saw in one frame, nothing more.
@Observable
@MainActor
final class CameraPreviewViewModel {
    /// The live preview host (the capture service). The view wraps the `UIView`
    /// it vends through `CameraPreviewView`; `nil` when no camera is recording
    /// this ride (the ride screen then offers no camera view).
    @ObservationIgnored let previewHost: CameraPreviewHost?

    /// The latest view-only detection boxes to draw over the preview, replaced
    /// each processed frame. Empty when nothing is seen.
    private(set) var boxes: [DetectionOverlayBox] = []

    init(previewHost: CameraPreviewHost?) {
        self.previewHost = previewHost
    }

    /// Whether there is a live preview to show at all (a host exists).
    var hasPreview: Bool { previewHost != nil }

    /// Replace the current boxes with the detector's latest frame. Called on the
    /// main actor by the detector's overlay seam.
    func update(boxes: [DetectionOverlayBox]) {
        self.boxes = boxes
    }

    /// Clear the boxes (e.g. when the preview is hidden or the ride ends).
    func clear() {
        boxes = []
    }
}
