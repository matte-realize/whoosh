import Foundation

/// Abstraction over saved-clip storage so the pinner, summary/history, and tests
/// are swappable and fakeable (rear-camera spec Requirement 8, design "Service
/// protocols: ClipRepository"). The SwiftData implementation (`SwiftDataClipRepository`,
/// task 15) is the default; `InMemoryClipRepository` backs unit tests and
/// previews. Clips live in a **separate** repository from `RideRecord` so the
/// shipped ride model never migrates (D-CAM8); the cascade on ride deletion runs
/// through a small cleanup hook.
///
/// ## Contract (non-negotiable; see privacy steering)
/// - **On-device only.** A `ClipRecord` references local paths and a local
///   `eventRef`; it is never uploaded, linked, logged, or put in a message. The
///   network layers must not reference clip types (enforced by the privacy
///   script).
/// - **Real deletion.** `delete`, `deleteAll(rideId:)`, and `deleteAll()` remove
///   records (and, in the file-backed world, their footage); deletion is real,
///   never a soft flag.
///
/// All operations `throws` so storage failures surface to the caller (matching
/// `RideRepository`). Implementations run on the main actor in this project
/// (default isolation; SwiftData's `ModelContext` is main-actor here).
protocol ClipRepository {
    /// Persist a clip, inserting a new record or updating the existing one with
    /// the same `id` (the pinner flips `pending` → `saved`/`endedEarly`).
    func save(_ clip: ClipRecord) throws

    /// All clips for a ride, most-recent-first (by `createdAt`, descending).
    func clips(rideId: UUID) throws -> [ClipRecord]

    /// The clip with the given `id`, or `nil` if none exists.
    func clip(id: UUID) throws -> ClipRecord?

    /// Permanently remove the clip with the given `id`. A missing id is a safe
    /// no-op.
    func delete(id: UUID) throws

    /// Permanently remove every clip for a ride (ride-deletion cascade).
    func deleteAll(rideId: UUID) throws

    /// Permanently remove every stored clip (Settings "Delete all clips").
    func deleteAll() throws

    /// All clips whose retention expiry is at or before `now` (the launch /
    /// foreground retention sweep).
    func expired(now: Date) throws -> [ClipRecord]

    /// Total bytes used by all stored clips (Settings "storage used").
    func totalBytes() throws -> Int64
}
