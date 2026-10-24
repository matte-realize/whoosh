import Foundation
import SwiftData

/// SwiftData persistence entity for a saved clip (rear-camera spec Requirement
/// 8; design "Entities" / D-CAM8). Clips live in a **separate** entity from
/// `RideRecord` so the shipped ride model never migrates; adding this `@Model`
/// to the shared container leaves existing ride data untouched (regression test
/// in `SwiftDataClipRepositoryTests`).
///
/// Mirrors the ride/crash repositories' blob approach: the full domain
/// `ClipRecord` is encoded as one JSON blob, with a few fields denormalized onto
/// the row for cheap querying:
///
/// - `id` for upsert and lookup,
/// - `rideId` for per-ride fetch and cascade delete,
/// - `createdAt` for most-recent-first ordering,
/// - `expiresAt` for the retention sweep.
///
/// Footage is on-device only: a `ClipRecord` carries local paths and a local
/// `eventRef`, never uploaded, linked, logged, or put in a message (enforced by
/// the privacy script's network-layer rule). Mapping between `ClipRecord` and
/// this entity happens only in `SwiftDataClipRepository`.
@Model
final class ClipRecordEntity {
    @Attribute(.unique) var id: UUID
    /// The owning ride, denormalized for per-ride fetch and the ride-deletion
    /// cascade.
    var rideId: UUID
    /// When the clip was created, denormalized for most-recent-first ordering.
    var createdAt: Date
    /// When the clip auto-deletes under retention, denormalized for the sweep.
    var expiresAt: Date
    /// Encoded `ClipRecord` (JSON). Decoded lazily by the repository, which
    /// skips (and logs) a row whose blob fails to decode.
    var encodedRecord: Data

    init(
        id: UUID,
        rideId: UUID,
        createdAt: Date,
        expiresAt: Date,
        encodedRecord: Data
    ) {
        self.id = id
        self.rideId = rideId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.encodedRecord = encodedRecord
    }
}
