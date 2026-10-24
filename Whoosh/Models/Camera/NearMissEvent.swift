import Foundation

/// A recorded near-miss / vehicle-detection event (rear-camera spec
/// Requirement 15, design "Detection events and near-miss records"). Stored
/// locally with the ride. The optional `localClipId` is a **local-only** link to
/// a pinned clip and must never be uploaded; `NearMissUploadMapper` drops it when
/// mapping to Role C's `near_misses` contract (events only, never video).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`, `Identifiable`.
struct NearMissEvent: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    let rideId: UUID
    let occurredAt: Date
    /// Latitude of the nearest accepted route point (may be absent).
    let latitude: Double?
    /// Longitude of the nearest accepted route point (may be absent).
    let longitude: Double?
    /// A short detector-supplied kind label (e.g. "approachingVehicle").
    let kind: String
    /// Detector confidence in 0...1.
    let confidence: Double
    /// A coarse relative-position hint (e.g. "left"/"center"/"right"), if any.
    let positionHint: String?
    /// Local-only id of the pinned clip, if one was saved. **Never uploaded.**
    let localClipId: UUID?

    init(
        id: UUID,
        rideId: UUID,
        occurredAt: Date,
        latitude: Double?,
        longitude: Double?,
        kind: String,
        confidence: Double,
        positionHint: String?,
        localClipId: UUID?
    ) {
        self.id = id
        self.rideId = rideId
        self.occurredAt = occurredAt
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.confidence = confidence
        self.positionHint = positionHint
        self.localClipId = localClipId
    }
}
