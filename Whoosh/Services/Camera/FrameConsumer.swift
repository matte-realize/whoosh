import CoreVideo
import Foundation

/// What a `FrameConsumer` declares about its frame needs (rear-camera spec
/// task 11, Requirement 4.3; design "FrameConsumer — exact contract"). The
/// pipeline uses `maxFramesPerSecond` to rate-limit (via `FrameDropPolicy`) and
/// passes the rest as hints.
nonisolated struct FrameConsumerConfiguration: Equatable, Sendable {
    /// The pipeline never delivers faster than this. Clamped to ≥ 1 fps by the
    /// drop policy. Teammate B's detector is expected to declare ≤ 10 fps.
    let maxFramesPerSecond: Double
    /// The pixel format the consumer prefers; a hint, honored when cheap.
    let preferredPixelFormat: OSType?
    /// The largest dimension (longer side, pixels) the consumer wants; a hint,
    /// honored when cheap. `nil` means no preference.
    let maxDimensionHint: Int?
    /// Whether the consumer wants the discontinuity flag surfaced so it can reset
    /// temporal state after an interruption/format change.
    let wantsDiscontinuityReset: Bool

    init(
        maxFramesPerSecond: Double,
        preferredPixelFormat: OSType? = nil,
        maxDimensionHint: Int? = nil,
        wantsDiscontinuityReset: Bool = true
    ) {
        self.maxFramesPerSecond = maxFramesPerSecond
        self.preferredPixelFormat = preferredPixelFormat
        self.maxDimensionHint = maxDimensionHint
        self.wantsDiscontinuityReset = wantsDiscontinuityReset
    }
}

/// A subscriber to the camera `FramePipeline` (rear-camera spec task 11,
/// Requirement 4; design "FrameConsumer — exact contract"). **This is the seam
/// Teammate B's vision detector plugs into.** The shape is frozen by the contract
/// freeze and does not change without a 3-way OK (iOS, Teammate B, Role C).
///
/// ## Contract (normative)
/// - `consume(_:)` is called **off the main actor**, **one frame at a time**,
///   on the consumer's own serial execution. It is `async`; the pipeline awaits
///   it on a per-consumer driver task, **never** on the capture queue, so a slow
///   consumer can never delay capture, the segment writer, or another consumer.
/// - A consumer **must not retain** the `VideoFrame` (or its `pixelBuffer`)
///   after `consume(_:)` returns. The buffer is read-only and comes from a small
///   capture pool; holding it starves capture. Copy if history is needed
///   (Requirement 4.6).
/// - `consume(_:)` **does not throw** into the pipeline; a consumer handles its
///   own failures. A repeatedly slow consumer is not removed — it just sees its
///   newer frames dropped (busy-drop) and is reported in stats (Requirement 4.7).
/// - A consumer may take longer than the frame interval; the pipeline drops
///   newer frames rather than queueing them (latest-wins, single slot).
///
/// ## How Teammate B adapts a `VehicleDetector` as a `FrameConsumer`
/// Teammate B's `WhooshVision.VehicleDetector` exposes a **synchronous**
/// `detect(in:orientation:timestamp:)` that takes a `CVPixelBuffer` and runs
/// 10–40 ms on one background serial queue. It becomes a consumer by wrapping
/// that call (the detector is also a `HazardDetector`, Requirement 4.9):
///
/// ```swift
/// // In Teammate B's package / integration (NOT added by this iOS job).
/// import CoreVideo
///
/// final class VehicleDetectorConsumer: FrameConsumer, HazardDetector {
///     let consumerID = "whoosh.vision.vehicle"
///     // ≤ 10 fps so the ~10–40 ms synchronous detect() keeps pace; the
///     // pipeline drops anything faster. Request a downscaled buffer as a hint.
///     let configuration = FrameConsumerConfiguration(
///         maxFramesPerSecond: 10,
///         preferredPixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
///         maxDimensionHint: 960,
///         wantsDiscontinuityReset: true
///     )
///     var onDetection: ((HazardDetection) -> Void)?
///     private let detector = VehicleDetector()
///
///     func pipelineDidStart(format: VideoFrame.Format) { detector.reset() }
///     func pipelineDidStop() { detector.reset() }
///
///     func consume(_ frame: VideoFrame) async {
///         // One frame at a time, off the main actor. The synchronous detect()
///         // call is fine here — the pipeline is awaiting us on our own driver,
///         // never on the capture queue, so this never blocks capture.
///         if frame.isDiscontinuity { detector.reset() } // reset temporal state
///         // Map VideoFrame.DisplayOrientation → CGImagePropertyOrientation.
///         let orientation = CGImagePropertyOrientation(rawValue: UInt32(frame.orientation.rawValue))!
///         // Do NOT retain frame.pixelBuffer past this call; copy inside if needed.
///         if let hit = detector.detect(in: frame.pixelBuffer,
///                                      orientation: orientation,
///                                      timestamp: frame.presentationTime) {
///             // Use the frame's wall-clock capture time, not inference-finish
///             // time, so near-miss clip windows align with the video.
///             let detection = HazardDetection(
///                 timestamp: frame.capturedAt,
///                 kind: hit.kind,
///                 confidence: hit.confidence,
///                 relativePositionHint: hit.positionHint
///             )
///             await MainActor.run { onDetection?(detection) } // deliver on main
///         }
///     }
///
///     func start() { /* DetectionCoordinator registers us with the pipeline */ }
///     func stop()  { /* DetectionCoordinator unregisters us */ }
/// }
/// ```
///
/// The detector **never** creates an `AVCaptureSession`, requests camera
/// permission, or writes video — `CameraCaptureService` and `CameraPermission`
/// own those (Requirement 4.9, design "HazardDetector seam update").
///
/// The members are `nonisolated` so they run on the consumer's own executor,
/// **off the main actor**, under the project's `MainActor`-default isolation
/// (design "Concurrency"). Only `onDetection` delivery hops back to the main
/// actor, inside the consumer.
protocol FrameConsumer: AnyObject, Sendable {
    /// Stable identifier for registration and diagnostics.
    nonisolated var consumerID: String { get }
    /// The consumer's frame needs (rate cap, format/dimension hints).
    nonisolated var configuration: FrameConsumerConfiguration { get }

    /// Process exactly one frame. Called off the main actor, one at a time.
    /// Return when done; do not retain the frame afterwards.
    nonisolated func consume(_ frame: VideoFrame) async

    /// Delivered off-main when the pipeline starts with the given active format.
    nonisolated func pipelineDidStart(format: VideoFrame.Format)
    /// Delivered off-main when the pipeline stops (or the consumer is removed).
    nonisolated func pipelineDidStop()
}
