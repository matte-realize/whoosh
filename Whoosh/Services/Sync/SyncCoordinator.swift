import Foundation

/// Owns the opt-in sync retry policy (Requirements 12.3, 12.4, 12.6).
///
/// The coordinator sits *beside* the ride state machine and never touches it:
/// recording, summaries, history, and local deletion all work with no network.
/// It is driven by three app-level events — a ride finished, a ride was deleted,
/// all rides were deleted — plus an `retryPending()` tick (app foreground).
///
/// Policy:
/// - **Local-first.** Callers persist the ride locally *before* handing it here;
///   the coordinator only mirrors that state to the backend. A sync failure
///   never affects the local ride.
/// - **Idempotent uploads.** `upload(_:)` upserts on `ride.id`, and the
///   coordinator never re-uploads a ride already marked `.synced`, so retries
///   can't create duplicate remote rows.
/// - **Pending on failure.** A failed upload marks the ride `.pending` locally;
///   `retryPending()` re-attempts every `.pending` ride.
/// - **Deletes propagate.** Deleting a ride records a tombstone and requests
///   remote deletion; the tombstone is kept if the delete fails and is drained
///   on the next `retryPending()`. `deleteAll` tombstones every previously
///   synced ride.
/// - **Disabled = nothing.** While `service.isEnabled` is `false` the coordinator
///   performs no uploads, deletes, retries, or local status changes at all.
///
/// Route privacy: before upload the route is trimmed with `RoutePrivacy.trim`
/// (default 160 m each end); the local copy stays complete.
///
/// ## Wiring (task 28)
/// This type is **not** wired into the composition root yet — sync is off and
/// the Settings "Sync rides to Whoosh map" toggle still reads "Coming soon".
/// When task 28 adds `SupabaseRideSyncService` and enables the toggle, the
/// composition root (`AppEnvironment`) will build one `SyncCoordinator` with the
/// real service, the shared `RideRepository`, and a
/// `UserDefaultsPendingRemoteDeleteStore`, then: call `rideDidFinish(_:)` after
/// a ride is saved, `rideWasDeleted(_:)` from the history/summary delete path,
/// `allRidesWereDeleted(previouslySynced:)` from the Settings "Delete all rides"
/// action, and `retryPending()` on `scenePhase` → `.active`.
@MainActor
final class SyncCoordinator {
    private let service: RideSyncService
    private let repository: RideRepository
    private let pendingDeletes: PendingRemoteDeleteStore
    private let trimMeters: Double
    /// Supplies the locally stored near-miss events for a ride so the coordinator
    /// can upsert them after the ride row is uploaded (rear-camera Req 15, task
    /// 28). Defaults to "none", so a coordinator built without a near-miss store
    /// (previews, sync-only tests) behaves exactly as before.
    private let nearMissEvents: (UUID) -> [NearMissEvent]

    init(
        service: RideSyncService,
        repository: RideRepository,
        pendingDeletes: PendingRemoteDeleteStore,
        trimMeters: Double = RoutePrivacy.defaultTrimMeters,
        nearMissEvents: @escaping (UUID) -> [NearMissEvent] = { _ in [] }
    ) {
        self.service = service
        self.repository = repository
        self.pendingDeletes = pendingDeletes
        self.trimMeters = trimMeters
        self.nearMissEvents = nearMissEvents
    }

    // MARK: Events

    /// Call after a finished ride has been saved locally. Stamps the ride's
    /// public-sharing state from the *current* global flag (not retroactive,
    /// Requirement 12.13), persists that stamp, then uploads it (when sync is
    /// enabled) and records the outcome as the ride's `syncStatus`.
    func rideDidFinish(_ ride: Ride, shareNewRidesPublicly: Bool = false) async {
        guard service.isEnabled else { return }
        // Demo rides are never uploaded (demo-mode spec Req 9.3); their local
        // sync status is left untouched.
        guard !ride.isDemo else { return }
        var stamped = ride
        if stamped.sharePublicly != shareNewRidesPublicly {
            stamped.sharePublicly = shareNewRidesPublicly
            try? repository.save(stamped)
        }
        await upload(stamped)
    }

    /// Call after a ride has been deleted locally. If it had been synced (or was
    /// pending), records a tombstone and requests remote deletion, keeping the
    /// tombstone if the delete fails so it is retried later.
    ///
    /// Per the privacy network invariant this runs only through a configured,
    /// enabled service. The user-initiated remote-delete exception while
    /// *background* sync is paused (Requirement 9.2 / 12.6) is expressed by the
    /// service reporting `isEnabled == true` whenever a remote row could exist
    /// (wired in 28f); a truly disabled/unconfigured service makes zero calls.
    func rideWasDeleted(_ ride: Ride) async {
        guard service.isEnabled else { return }
        // A ride that never left the device has no remote row to delete.
        guard ride.syncStatus != .localOnly else { return }
        pendingDeletes.add(ride.id)
        await drainDelete(ride.id)
    }

    /// Call after "Delete all rides" has wiped local storage. `previouslySynced`
    /// is the set of ride ids that had been uploaded (synced or pending) and so
    /// still need remote deletion.
    func allRidesWereDeleted(previouslySynced ids: [UUID]) async {
        guard service.isEnabled else { return }
        for id in ids {
            pendingDeletes.add(id)
        }
        for id in pendingDeletes.allPending() {
            await drainDelete(id)
        }
    }

    /// User turned global sharing OFF and chose to also unshare already-shared
    /// rides (Requirement 12.14). For each ride, flips `sharePublicly` to false
    /// locally and asks the backend to unshare it. A failure leaves the local
    /// flag cleared (so the UI reflects the user's intent) and the ride marked
    /// for a later retry via `retryPending()`.
    func unshareRides(_ rides: [Ride]) async {
        guard service.isEnabled else { return }
        for ride in rides where ride.sharePublicly {
            var updated = ride
            updated.sharePublicly = false
            try? repository.save(updated)
            guard ride.syncStatus != .localOnly else { continue }
            await setRemoteSharing(id: ride.id, shared: false)
        }
    }

    /// Retry trigger (app foreground): upload every `.pending` ride and drain
    /// every pending remote delete. Safe to call repeatedly; never double-uploads
    /// a `.synced` ride.
    func retryPending() async {
        guard service.isEnabled else { return }

        // Uploads: retry rides left pending by an earlier failure. Demo rides
        // are never uploaded (demo-mode spec Req 9.3), even if marked pending.
        let rides = (try? repository.allRides()) ?? []
        for ride in rides where ride.syncStatus == .pending && !ride.isDemo {
            await upload(ride)
        }

        // Near misses: a ride can be `.synced` while its events failed to
        // upsert earlier (the ride is safely synced, but the near misses are
        // not). Re-attempt them here; the upsert is harmless to repeat.
        for ride in rides where ride.syncStatus == .synced && !ride.isDemo {
            await uploadNearMisses(for: ride)
        }

        // Deletes: drain tombstones from offline deletions.
        for id in pendingDeletes.allPending() {
            await drainDelete(id)
        }
    }

    // MARK: Helpers

    /// Requests a remote sharing update, swallowing a failure (the local flag is
    /// already updated; a retry can re-apply it). Keeps sync failures from
    /// affecting local data.
    private func setRemoteSharing(id: UUID, shared: Bool) async {
        try? await service.setSharing(id: id, shared: shared)
    }

    /// Uploads a ride (privacy-trimmed) and persists the resulting status.
    /// Never uploads a ride already `.synced`.
    ///
    /// A `RideSyncTerminalOutcome` thrown by the service records a terminal
    /// status and is never retried: `.failed` (a limit pre-check or a `23514`
    /// check violation) → `.failed`; `.localOnly` (fewer than 2 points after
    /// trimming, or a demo ride) → `.localOnly`. Any other error is retryable
    /// → `.pending`.
    private func upload(_ ride: Ride) async {
        guard ride.syncStatus != .synced else { return }
        var trimmed = ride
        trimmed.points = RoutePrivacy.trim(points: ride.points, meters: trimMeters)
        do {
            try await service.upload(trimmed)
            persist(ride, status: .synced)
            // The ride row exists now, so the `near_misses.ride_id` FK resolves.
            await uploadNearMisses(for: ride)
        } catch RideSyncTerminalOutcome.failed {
            persist(ride, status: .failed)
        } catch RideSyncTerminalOutcome.localOnly {
            persist(ride, status: .localOnly)
        } catch {
            persist(ride, status: .pending)
        }
    }

    /// Upserts the ride's locally stored near-miss events (rear-camera Req 15,
    /// task 28). Called only after the ride row is uploaded. Drops demo events
    /// (never uploaded) and any event inside the privacy-trim zone, then maps to
    /// the contract shape with the ride's stamped `share_publicly` flag. A
    /// failure is swallowed: it never reverts the ride's `.synced` status (the
    /// ride is safely uploaded) and a later `retryPending()` re-attempts it. A
    /// double send is harmless at hackathon scale (server ids are generated and
    /// the batch is re-sent only on an earlier failure).
    private func uploadNearMisses(for ride: Ride) async {
        let stored = nearMissEvents(ride.id).filter { !$0.isDemo }
        guard !stored.isEmpty else { return }
        let uploadable = NearMissTrimFilter.uploadable(
            events: stored,
            points: ride.points,
            meters: trimMeters
        )
        let payloads = uploadable.compactMap {
            NearMissUploadMapper.mapIfUploadable($0, sharePublicly: ride.sharePublicly)
        }
        guard !payloads.isEmpty else { return }
        try? await service.uploadNearMisses(payloads)
    }

    /// Requests remote deletion for an id, removing the tombstone only on
    /// success so a failure is retried on the next `retryPending()`.
    private func drainDelete(_ id: UUID) async {
        do {
            try await service.deleteRemote(id: id)
            pendingDeletes.remove(id)
        } catch {
            // Keep the tombstone; it will be retried later.
        }
    }

    /// Writes the ride back to local storage with an updated `syncStatus`.
    /// A persistence failure here never affects the (already-saved) ride.
    private func persist(_ ride: Ride, status: SyncStatus) {
        guard ride.syncStatus != status else { return }
        var updated = ride
        updated.syncStatus = status
        try? repository.save(updated)
    }
}
