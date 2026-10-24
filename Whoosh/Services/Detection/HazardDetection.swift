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
struct HazardDetection: Equatable, Sendable {
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
/// Contract (also see the design "Future seams" section):
/// - **On-device.** Immediate safety alerts must not depend on a network.
/// - **Non-blocking.** Implementations MUST never block, slow, or stop ride
///   recording. Heavy frame processing/inference runs off the main actor (a
///   dedicated actor or `@concurrent` work); only `onDetection` delivery hops
///   back to the main actor.
/// - **Honest.** Detection is experimental; copy must not claim collision
///   prediction or prevention.
///
/// The MVP ships only `NoopDetector`; no camera permission is requested anywhere
/// in the MVP (the Home card, the ride-screen "Rear detection off" chip, and the
/// Settings "Soon" row are inert placeholders).
protocol HazardDetector: AnyObject {
    /// Delivered on the main actor as detections occur.
    var onDetection: ((HazardDetection) -> Void)? { get set }
    /// Begin detection. Must not block the caller.
    func start()
    /// Stop detection and release any resources.
    func stop()
}

/// The MVP's inert `HazardDetector`: never emits, never requests the camera.
///
/// Injected at the composition root so the ride flow runs unchanged until a real
/// detector (Role B) replaces it.
final class NoopDetector: HazardDetector {
    var onDetection: ((HazardDetection) -> Void)?

    init() {}

    /// No-op: emits no detections and acquires no camera.
    func start() {}
    /// No-op.
    func stop() {}
}
