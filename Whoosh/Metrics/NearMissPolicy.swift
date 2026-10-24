import Foundation

/// Pure policy deciding whether an incoming `HazardDetection` becomes a
/// near-miss **event** and whether a clip should be **pinned** (rear-camera spec
/// task 10, Requirements 15.1, 15.2; design "Detection events and near-miss
/// records").
///
/// Pure, framework-free (Metrics layer: Models + Foundation only), like
/// `LocationSnapshotPolicy`. No AVFoundation, no clock object — `now` is passed
/// in the `Context`. The confidence threshold is supplied by the caller
/// (Teammate B's measured number), so "detection pinning is off until measured
/// thresholds exist" lives in the caller, not here.
///
/// Decision rules (in order):
/// 1. confidence < threshold ⇒ `.ignore` (not even an event).
/// 2. within `autoPinCooldown` of the last accepted event ⇒ `.ignore` (part of
///    the same event; no new event, no new pin).
/// 3. camera not recording ⇒ `.recordNoPin` (cannot pin; event still recorded).
/// 4. storage not `ok` (warn/stop) ⇒ `.recordNoPin` (auto-pins refused).
/// 5. per-ride auto-pin cap reached ⇒ `.recordNoPin`.
/// 6. otherwise ⇒ `.recordAndPin`.
enum NearMissPolicy {

    /// The decision for one detection.
    enum Decision: Equatable, Sendable {
        /// Below threshold or within cooldown: do nothing.
        case ignore
        /// Record a near-miss event but do not pin a clip (storage, cap, or the
        /// camera is not recording).
        case recordNoPin
        /// Record a near-miss event and pin a detection clip.
        case recordAndPin

        /// Whether a `NearMissEvent` should be stored for this decision.
        var recordsEvent: Bool {
            switch self {
            case .ignore: return false
            case .recordNoPin, .recordAndPin: return true
            }
        }

        /// Whether a clip should be pinned for this decision.
        var pinsClip: Bool { self == .recordAndPin }
    }

    /// The non-detection inputs the decision needs.
    struct Context: Equatable, Sendable {
        /// The instant the detection is being evaluated.
        var now: Date
        /// The minimum confidence to accept (Teammate B's measured number).
        var confidenceThreshold: Double
        /// When the last accepted near-miss event occurred, if any.
        var lastAcceptedEventAt: Date?
        /// How many auto-pins have already happened this ride.
        var autoPinsThisRide: Int
        /// Current free-space status.
        var storageStatus: StorageStatus
        /// Whether the camera is actively recording (can a clip be pinned?).
        var cameraRecording: Bool

        init(
            now: Date,
            confidenceThreshold: Double,
            lastAcceptedEventAt: Date?,
            autoPinsThisRide: Int,
            storageStatus: StorageStatus,
            cameraRecording: Bool
        ) {
            self.now = now
            self.confidenceThreshold = confidenceThreshold
            self.lastAcceptedEventAt = lastAcceptedEventAt
            self.autoPinsThisRide = autoPinsThisRide
            self.storageStatus = storageStatus
            self.cameraRecording = cameraRecording
        }
    }

    /// Decide what to do with `detection`.
    static func decide(
        detection: HazardDetection,
        context: Context,
        tuning: RideCameraTuning
    ) -> Decision {
        // 1. Confidence gate (>= threshold is accepted).
        guard detection.confidence >= context.confidenceThreshold else { return .ignore }

        // 2. Cooldown: within the cooldown since the last accepted event ⇒ same
        //    event. The boundary (exactly cooldown elapsed) is accepted.
        if let last = context.lastAcceptedEventAt {
            let elapsed = context.now.timeIntervalSince(last)
            if elapsed < tuning.autoPinCooldown { return .ignore }
        }

        // 3–5. Event is accepted; decide whether a pin is allowed.
        if !context.cameraRecording { return .recordNoPin }
        if context.storageStatus != .ok { return .recordNoPin }
        if context.autoPinsThisRide >= tuning.maxAutoPinsPerRide { return .recordNoPin }

        return .recordAndPin
    }

    /// Build a `NearMissEvent` from a detection and the ride context. The nearest
    /// accepted route coordinate (looked up by the caller) may be absent; the
    /// local clip id is linked later only when a pin actually succeeds, so it is
    /// `nil` here.
    static func makeEvent(
        id: UUID,
        rideId: UUID,
        detection: HazardDetection,
        latitude: Double?,
        longitude: Double?
    ) -> NearMissEvent {
        NearMissEvent(
            id: id,
            rideId: rideId,
            occurredAt: detection.timestamp,
            latitude: latitude,
            longitude: longitude,
            kind: detection.kind,
            confidence: detection.confidence,
            positionHint: detection.relativePositionHint,
            localClipId: nil
        )
    }
}
