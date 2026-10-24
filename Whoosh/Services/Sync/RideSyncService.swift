import Foundation

/// Opt-in cloud sync of finished rides (Requirement 12).
///
/// All sync access goes through this abstraction so the MVP can ship a no-op
/// and a Supabase implementation can be swapped in — and faked in tests —
/// without touching the ride engine or the `SyncCoordinator`. The service is
/// the *only* place that may talk to the network (`Services/Sync` is the single
/// allowed network folder per the privacy steering); everything above it stays
/// local-first and offline-safe.
///
/// ## Contract
/// - `upload(_:)` is an **idempotent upsert on `ride.id`**: calling it more than
///   once for the same ride never creates a duplicate remote row, so retries
///   are safe. The route is privacy-trimmed (`RoutePrivacy.trim`) by the caller
///   before upload; the local copy stays complete.
/// - `deleteRemote(id:)` removes the remote row for a ride the user deleted
///   locally; it is also safe to call repeatedly.
/// - Both are `async throws`: a failure (offline, server error) is surfaced so
///   the `SyncCoordinator` can mark the ride `pending` / keep a delete tombstone
///   and retry later. A sync failure must never affect local recording or data.
///
/// Concrete network work (the Supabase implementation, task 28) runs off the
/// main actor; the protocol itself is actor-agnostic.
protocol RideSyncService {
    /// Whether the user has opted in to cloud sync. While `false`, the
    /// `SyncCoordinator` performs no uploads, deletes, or retries at all.
    var isEnabled: Bool { get }

    /// Upload (upsert) a finished ride. Idempotent on `ride.id`.
    func upload(_ ride: Ride) async throws

    /// Request remote deletion of the ride with the given `id`. Idempotent;
    /// deleting an already-absent remote row is not an error.
    func deleteRemote(id: UUID) async throws

    /// Update the remote `share_publicly` flag for a ride (Requirement 12.11–
    /// 12.15). The Supabase implementation re-sends the full row so a partial
    /// update can't trip the backend's `rides_active_within_elapsed` check.
    /// Idempotent on `id`.
    func setSharing(id: UUID, shared: Bool) async throws

    /// Upsert the near-miss events for a ride (rear-camera spec Requirement 15,
    /// task 28). Called by the `SyncCoordinator` **after** the ride row is
    /// uploaded, so the `near_misses.ride_id` foreign key always resolves. The
    /// payloads are already privacy-filtered and mapped (no footage reference,
    /// trim-zone and demo events dropped) by the caller. Idempotent on each
    /// event id; a failure is thrown so the coordinator can retry later.
    func uploadNearMisses(_ payloads: [NearMissUploadMapper.Payload]) async throws
}
