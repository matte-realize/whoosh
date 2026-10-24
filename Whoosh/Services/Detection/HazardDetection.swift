import Foundation

/// A single hazard-detection event emitted by a `HazardDetector`.
///
/// **Integration point for the vision teammate (Role B).** This is the shape the
/// detection subsystem produces; the ride-recording engine does not depend on
/// how detections are produced (camera, Vision, Core ML, etc.), only on this
/// value.
///
/// Deliberately *not* locked into an enum of hazard classes or a specific
/// geometry: `kind` is an open `String` (e.g. `"vehicle"`) and
/// `relativePositionHint` is a free-form optional (e.g. `"left"`/`"center"`/
/// `"right"`). This keeps enough information to later tie a detection to a
/// `RoutePoint` by `timestamp` for **near-miss logging** (Requirement 8.6)
/// without a redesign, while the MVP implements none of that.
///
/// `Sendable` because detection work runs off the main actor (a dedicated actor
/// or `@concurrent` work); only `onDetection` delivery hops back to the main
/// actor. Pure value type, Foundation-only, no framework lock-in.
nonisolated struct HazardDetection: Equatable, Sendable {
    /// When the detection occurred; alignable with a `RoutePoint.timestamp`
    /// for future near-miss logging.
    let timestamp: Date
    /// The kind of hazard, kept open (e.g. `"vehicle"`) rather than an enum so
    /// the vision team can grow classes without a protocol change.
    let kind: String
    /// Detector confidence in `0...1`.
    let confidence: Double
    /// Optional coarse position relative to the rider (e.g. `"left"`,
    /// `"center"`, `"right"`); `nil` when unknown.
    let relativePositionHint: String?

    init(
        timestamp: Date,
        kind: String,
        confidence: Double,
        relativePositionHint: String? = nil
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.confidence = confidence
        self.relativePositionHint = relativePositionHint
    }
}

/// Abstraction for rear-vehicle (and future) hazard detection.
///
/// **Integration point for the vision teammate (Role B).** Implement this
/// against the abstraction; the ride-recording code does not need to change.
///
/// ## Contract (rear-camera spec "HazardDetector seam update", Requirement 4.9)
/// - **A camera-based detector is also a `FrameConsumer`.** It conforms to both
///   `HazardDetector` and `FrameConsumer` and receives frames only through the
///   `FramePipeline`; the `DetectionCoordinator` (not the detector) registers it
///   with the pipeline. See `VisionVehicleConsumer`.
/// - **Never owns capture.** A detector creates no capture session, requests
///   no camera permission, and writes no video. The camera capture service and
///   the camera-permission seam own those. Camera permission belongs to *rear
///   camera recording*, not to detection; the privacy script no longer allows
///   capture APIs in `Services/Detection`.
/// - **`start()` / `stop()`.** `start()` begins inference (and, for the real
///   detector, loads the model once); `stop()` ends inference and releases model
///   resources. The coordinator pairs these with pipeline register/remove. Both
///   are non-blocking.
/// - **On-device.** Immediate safety alerts must not depend on a network.
/// - **Non-blocking.** Implementations MUST never block, slow, or stop ride
///   recording. Heavy frame processing/inference runs off the main actor (a
///   dedicated serial queue or actor); only `onDetection` delivery hops back to
///   the main actor.
/// - **Timestamp.** `HazardDetection.timestamp` SHOULD be the triggering frame's
///   `VideoFrame.capturedAt` (wall-clock), not inference-completion time, so
///   near-miss clip windows align with the video.
/// - **When it runs.** Only while the camera state is `recording` or `degraded`
///   and rear detection is enabled; it is paused automatically on interruption
///   (frames stop; the discontinuity flag is set on resume).
/// - **Honest.** Detection is experimental; copy must not claim collision
///   prediction or prevention, and it cannot guarantee detection or delivery.
///
/// A detection flows `DetectionCoordinator` → `NearMissPolicy` → (a) a local
/// `NearMissEvent`, (b) a clip pin if enabled, (c) `AlertManager` after the
/// existing gate/cooldown.
protocol HazardDetector: AnyObject {
    /// Delivered on the main actor as detections occur.
    var onDetection: ((HazardDetection) -> Void)? { get set }
    /// Begin detection. Must not block the caller.
    func start()
    /// Stop detection and release any resources.
    func stop()
}

/// The inert `HazardDetector`: never emits, never registers a consumer, never
/// requests the camera.
///
/// Injected at the composition root so the ride flow runs unchanged until a real
/// detector (Role B's `VisionVehicleConsumer`) replaces it. The no-op never
/// registers a frame consumer with the pipeline; camera permission belongs to
/// rear camera recording, not to detection (rear-camera spec "HazardDetector
/// seam update").
final class NoopDetector: HazardDetector {
    var onDetection: ((HazardDetection) -> Void)?

    init() {}

    /// No-op: emits no detections and acquires no camera.
    func start() {}
    /// No-op.
    func stop() {}
}
