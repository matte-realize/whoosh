import Foundation

/// A single vehicle box to **draw** over the live camera preview on the active
/// ride screen (owner device-testing feedback: "the user should be able to see
/// the camera" with the vision detections drawn on top). This is a **view-only**
/// value: it exists purely so the ride screen can show the rider what the
/// experimental detector is looking at, and it is **not** part of the frozen
/// `HazardDetection` seam or the alert / near-miss path. Nothing here changes
/// detection, recording, or what leaves the device — footage and frames never
/// leave the phone, and these boxes are discarded as soon as the next frame's
/// boxes arrive.
///
/// Foundation-only value type (Models layer): the rect is normalized `0...1`
/// with a **top-left origin in the displayed (rider-facing) image**, so a view
/// can map it with a single `GeometryReader` without importing Vision, CoreVideo,
/// or AVFoundation. `Equatable`, `Identifiable`, `Sendable`.
///
/// Honesty (privacy steering): a box is only what the model saw in one frame; it
/// is experimental and cannot guarantee detection or delivery. The `label` and
/// `confidence` are shown as-is and never framed as a promise.
nonisolated struct DetectionOverlayBox: Identifiable, Equatable, Sendable {
    /// Stable-per-frame id so SwiftUI can diff the boxes; a fresh UUID per box is
    /// fine because the whole set is replaced each frame.
    let id: UUID
    /// The detected class label (e.g. `"car"`, `"truck"`); shown as-is.
    let label: String
    /// Detector confidence in `0...1`; shown as a percentage, never a promise.
    let confidence: Double
    /// Left edge, normalized `0...1` in the displayed image (x increases right).
    let x: Double
    /// Top edge, normalized `0...1` in the displayed image (y increases down).
    let y: Double
    /// Width, normalized `0...1`.
    let width: Double
    /// Height, normalized `0...1`.
    let height: Double
    /// Whether this is the box the approach heuristic flagged as getting closer,
    /// so the view can highlight it in the alert color. Experimental only.
    let isApproaching: Bool

    init(
        id: UUID = UUID(),
        label: String,
        confidence: Double,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        isApproaching: Bool = false
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isApproaching = isApproaching
    }
}
