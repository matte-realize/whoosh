import Foundation
import SwiftData

/// SwiftData persistence entity for a crash-alert record (spec Requirement
/// 11.1). Mirrors the ride repository's blob approach: the full domain
/// `CrashAlertRecord` (event + location snapshots + rendered text + ordered
/// attempts) is encoded as a single JSON blob, with a few fields denormalized
/// onto the row for cheap querying:
///
/// - `id` (= `crashEventId`) for upsert and lookup,
/// - `detectedAt` for most-recent-first ordering and retention purge,
/// - `stateRaw` for the active-event relaunch lookup.
///
/// The encoded record **never contains a full phone number** — attempts carry
/// only the masked last-2-digits (Requirement 11.3), so the blob is safe. The
/// denormalized columns likewise carry no contact data. Mapping between
/// `CrashAlertRecord` and this entity happens only in
/// `SwiftDataCrashAlertRepository`.
@Model
final class CrashAlertRecordEntity {
    @Attribute(.unique) var id: UUID
    /// The event detection time, denormalized for ordering and retention purge.
    var detectedAt: Date
    /// Raw `CrashEventState` value, denormalized for the active-event lookup.
    var stateRaw: String
    /// Encoded `CrashAlertRecord` (JSON). Decoded lazily by the repository,
    /// which skips (and logs) a row whose blob fails to decode.
    var encodedRecord: Data

    init(
        id: UUID,
        detectedAt: Date,
        stateRaw: String,
        encodedRecord: Data
    ) {
        self.id = id
        self.detectedAt = detectedAt
        self.stateRaw = stateRaw
        self.encodedRecord = encodedRecord
    }
}
