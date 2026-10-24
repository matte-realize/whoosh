import Foundation

/// Where a near-miss event came from (incident-mapping migration
/// `20261024130000_incident_mapping_and_indexes.sql`). A **detected** event is
/// produced by the experimental rear-vehicle detector and always carries a
/// confidence score; a **rider-reported** event is logged by the rider and has
/// no score. Stored as the exact `near_misses.source` string values.
enum NearMissSource: String, Equatable, Codable, Sendable {
    case detected
    case riderReported = "rider_reported"
}

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
    /// Latitude of the nearest accepted route point (may be absent — e.g. the
    /// event fell inside the privacy-trim zone, in which case it is never
    /// uploaded).
    let latitude: Double?
    /// Longitude of the nearest accepted route point (may be absent).
    let longitude: Double?
    /// A short detector-supplied kind label (e.g. "vehicle").
    let kind: String
    /// Detector confidence in 0...1. Carries a value for a detected event; a
    /// rider-reported event's score is dropped at upload (contract: null).
    let confidence: Double
    /// A coarse relative-position hint (e.g. "left"/"center"/"right"), if any.
    let positionHint: String?
    /// Where the event came from. Defaults to `.detected` (the only source that
    /// exists today); rider-reported logging is a future feature.
    let source: NearMissSource
    /// Whether the event was produced by a demo ride / demo-mode detector.
    /// Demo events are stored locally (so the demo shows markers) but are
    /// **never uploaded** (demo-mode spec Req 9.3, privacy steering). Not part
    /// of the upload contract; dropped by the mapper.
    let isDemo: Bool
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
        source: NearMissSource = .detected,
        isDemo: Bool = false,
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
        self.source = source
        self.isDemo = isDemo
        self.localClipId = localClipId
    }
}
