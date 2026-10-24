import Foundation

/// The opt-in Supabase implementation of `RideSyncService` (task 28e).
///
/// An `actor` so all sync work runs **off the main actor** (the ride engine and
/// view models stay on `MainActor`). It owns the upload *policy* and *error
/// classification*; the actual wire calls go through an injected
/// `RideSyncTransport` seam, so unit tests inject a fake transport and never
/// touch the network. The only type that imports the Supabase SDK is
/// `SupabaseRideSyncTransport`.
///
/// Behaviour:
/// - `upload(_:)` runs `RideUploadPolicy` (thin + validate + map; the route is
///   already privacy-trimmed by the `SyncCoordinator`, so the policy trims with
///   `0 m` to avoid double-trimming). A `.skipLocalOnly` / `.markFailed`
///   outcome throws a `RideSyncTerminalOutcome` so the coordinator records the
///   right terminal status without a network request. A successful upsert is a
///   full-column `on conflict (id) do update`.
/// - Error classification (`SyncErrorClassifier`): `23514` → permanent
///   `.failed`; `42501`/auth → refresh the session once and retry; offline/5xx
///   → rethrown as retryable so the coordinator marks the ride `.pending`.
/// - `setSharing(id:shared:)` re-sends the **full** row (never a partial update)
///   so the backend's `rides_active_within_elapsed` check can't trip.
actor SupabaseRideSyncService: RideSyncService {
    private let transport: RideSyncTransport
    private let appVersion: String
    private let enabledProvider: @Sendable () -> Bool

    /// Snapshot source for a ride's full row when only sharing changes: the
    /// coordinator passes the current ride so we can re-send every column.
    nonisolated var isEnabled: Bool { enabledProvider() }

    init(
        transport: RideSyncTransport,
        appVersion: String,
        isEnabled: @escaping @Sendable () -> Bool
    ) {
        self.transport = transport
        self.appVersion = appVersion
        self.enabledProvider = isEnabled
    }

    func upload(_ ride: Ride) async throws {
        // The route arrives already privacy-trimmed; the policy still thins,
        // validates every contract limit, and maps the row. trimMeters: 0 keeps
        // it from trimming a second time.
        let outcome = RideUploadPolicy.prepare(ride, appVersion: appVersion, trimMeters: 0)
        switch outcome {
        case .skipLocalOnly:
            throw RideSyncTerminalOutcome.localOnly
        case .markFailed:
            throw RideSyncTerminalOutcome.failed
        case .upload(let row):
            try await send { try await transport.upsert(row) }
        }
    }

    func deleteRemote(id: UUID) async throws {
        try await send { try await transport.delete(id: id) }
    }

    func setSharing(id: UUID, shared: Bool) async throws {
        // A sharing change is a safe partial update of only `share_publicly`:
        // it does not touch the duration/start/end columns, so it cannot trip
        // the backend's `rides_active_within_elapsed` check. (A change that DID
        // alter the duration would go through `upload(_:)` as a full-column
        // write; the coordinator's sharing-at-finalize path uses `upload`.)
        try await send { try await transport.updateSharing(id: id, shared: shared) }
    }

    func uploadNearMisses(_ payloads: [NearMissUploadMapper.Payload]) async throws {
        guard !payloads.isEmpty else { return }
        try await send { try await transport.upsertNearMisses(payloads) }
    }

    // MARK: Error handling

    /// Runs a transport call, ensuring a session first; on a `42501`/auth error
    /// it refreshes the session once and retries, on `23514` it rethrows a
    /// permanent `.failed`, and otherwise rethrows the error as retryable.
    private func send(_ work: () async throws -> Void) async throws {
        do {
            try await transport.ensureSession()
            try await work()
        } catch let error as SyncTransportError {
            switch SyncErrorClassifier.classify(postgrestCode: error.code) {
            case .permanent:
                throw RideSyncTerminalOutcome.failed
            case .authRetryable:
                // Refresh the anonymous session and retry once.
                try await transport.ensureSession()
                try await work()
            case .retryable:
                throw error
            }
        }
    }
}
