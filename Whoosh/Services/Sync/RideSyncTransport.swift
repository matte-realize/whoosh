import Foundation

/// The low-level network seam under `SupabaseRideSyncService` (task 28e).
///
/// Splitting the transport out from the service means the Supabase SDK lives in
/// exactly one type (`SupabaseRideSyncTransport`) and every unit test can inject
/// a fake transport — no test ever touches the network. The service owns the
/// *policy* (trim/thin/validate via `RideUploadPolicy`, error classification,
/// status decisions); the transport owns only the wire calls.
///
/// All methods run off the main actor (the Supabase implementation is an
/// `actor`). A failure is thrown as a `SyncTransportError` so the service can
/// classify it with `SyncErrorClassifier`.
protocol RideSyncTransport: Sendable {
    /// Ensure there is a valid anonymous session (sign in or refresh). Called
    /// before the first request and again after an auth-class failure.
    func ensureSession() async throws

    /// Full-column upsert of a prepared row, `on conflict (id) do update`.
    func upsert(_ row: RideUploadRow) async throws

    /// Delete the remote ride row by `id`. Deleting an absent row is not an error.
    func delete(id: UUID) async throws

    /// Update only the `share_publicly` flag for a ride by `id`. This is a safe
    /// partial update: it never touches `active_duration_s`/`started_at`/
    /// `ended_at`, so it cannot trip the backend's `rides_active_within_elapsed`
    /// check (that concern only applies to writes that change the duration).
    func updateSharing(id: UUID, shared: Bool) async throws

    /// Upsert a batch of near-miss rows into `near_misses`. `user_id` defaults to
    /// `auth.uid()` on the server, so it is not part of the payload; `id` is
    /// server-generated (`gen_random_uuid()`), so duplicate inserts from a retry
    /// are acceptable at hackathon scale (the coordinator only re-sends a ride's
    /// events on an earlier failure). An empty batch is a no-op.
    func upsertNearMisses(_ rows: [NearMissUploadMapper.Payload]) async throws
}

/// A transport-layer failure carrying the PostgREST error `code` (when the
/// server returned one) so the service can classify it without importing the
/// Supabase SDK. A `nil` `code` means a transport/offline error (retryable).
nonisolated struct SyncTransportError: Error, Sendable {
    let code: String?
    let message: String

    init(code: String?, message: String) {
        self.code = code
        self.message = message
    }
}
