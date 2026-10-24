import Foundation
import SwiftData

/// SwiftData persistence entity for a near-miss event (rear-camera spec
/// Requirement 15, task 28). Events live in a **separate** entity from
/// `RideRecord` so the shipped ride model never migrates; adding this `@Model`
/// to the shared live container leaves existing ride data untouched (the same
/// D-CAM8 pattern as `ClipRecordEntity` / `CrashAlertRecordEntity`).
///
/// Mirrors the blob approach: the full domain `NearMissEvent` is encoded as one
/// JSON blob, with a few fields denormalized onto the row for cheap querying:
///
/// - `id` for upsert and lookup,
/// - `rideId` for per-ride fetch and the ride-deletion cascade,
/// - `occurredAt` for oldest-first ordering (events align with the route),
/// - `isDemo` so demo events are easy to exclude from upload.
///
/// The event carries a **local-only** clip id that is never uploaded; the sync
/// path maps only through `NearMissUploadMapper`, which drops it (Role C
/// receives events only, never video). Mapping between `NearMissEvent` and this
/// entity happens only in `SwiftDataNearMissRepository`.
@Model
final class NearMissEventEntity {
    @Attribute(.unique) var id: UUID
    /// The owning ride, denormalized for per-ride fetch and the cascade.
    var rideId: UUID
    /// When the event occurred, denormalized for oldest-first ordering.
    var occurredAt: Date
    /// Whether the event came from a demo ride / demo detector (never uploaded).
    var isDemo: Bool
    /// Encoded `NearMissEvent` (JSON). Decoded lazily by the repository, which
    /// skips (and logs) a row whose blob fails to decode.
    var encodedEvent: Data

    init(
        id: UUID,
        rideId: UUID,
        occurredAt: Date,
        isDemo: Bool,
        encodedEvent: Data
    ) {
        self.id = id
        self.rideId = rideId
        self.occurredAt = occurredAt
        self.isDemo = isDemo
        self.encodedEvent = encodedEvent
    }
}
