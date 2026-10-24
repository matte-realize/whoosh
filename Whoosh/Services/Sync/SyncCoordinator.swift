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

    init(
        service: RideSyncService,
        repository: RideRepository,
        pendingDeletes: PendingRemoteDeleteStore,
        trimMeters: Double = RoutePrivacy.defaultTrimMeters
    ) {
        self.service = service
        self.repository = repository
        self.pendingDeletes = pendingDeletes
        self.trimMeters = trimMeters
    }

    // MARK: Events

    /// Call after a finished ride has been saved locally. Uploads it (when sync
    /// is enabled) and records the outcome as the ride's `syncStatus`.
    func rideDidFinish(_ ride: Ride) async {
        guard service.isEnabled else { return }
        await upload(ride)
    }

    /// Call after a ride has been deleted locally. If it had been synced (or was
    /// pending), records a tombstone and requests remote deletion, keeping the
    /// tombstone if the delete fails so it is retried later.
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

    /// Retry trigger (app foreground): upload every `.pending` ride and drain
    /// every pending remote delete. Safe to call repeatedly; never double-uploads
    /// a `.synced` ride.
    func retryPending() async {
        guard service.isEnabled else { return }

        // Uploads: retry rides left pending by an earlier failure.
        let rides = (try? repository.allRides()) ?? []
        for ride in rides where ride.syncStatus == .pending {
            await upload(ride)
        }

        // Deletes: drain tombstones from offline deletions.
        for id in pendingDeletes.allPending() {
            await drainDelete(id)
        }
    }

    // MARK: Helpers

    /// Uploads a ride (privacy-trimmed) and persists the resulting status.
    /// Never uploads a ride already `.synced`.
    private func upload(_ ride: Ride) async {
        guard ride.syncStatus != .synced else { return }
        var trimmed = ride
        trimmed.points = RoutePrivacy.trim(points: ride.points, meters: trimMeters)
        do {
            try await service.upload(trimmed)
            persist(ride, status: .synced)
        } catch {
            persist(ride, status: .pending)
        }
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
