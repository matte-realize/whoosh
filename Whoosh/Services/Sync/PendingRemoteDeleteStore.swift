import Foundation

/// A durable set of "remote delete" tombstones: ride ids whose local record has
/// already been deleted but whose remote row still needs to be removed
/// (Requirement 12.6).
///
/// When the user deletes a synced ride (or runs "Delete all rides") while
/// offline, the local deletion happens immediately and the ride's id is
/// recorded here. On the next sync opportunity the `SyncCoordinator` drains the
/// list, calling `RideSyncService.deleteRemote(id:)` for each; an id is removed
/// only after its remote delete succeeds, so a failed delete is retried later.
///
/// The store is persistent because a tombstone must outlive an app relaunch —
/// otherwise an offline delete would silently fail to propagate. Lives under
/// `Services/Sync` alongside the sync service; it holds only ride ids (UUIDs),
/// never route data.
protocol PendingRemoteDeleteStore {
    /// All ride ids awaiting remote deletion. Order is not significant.
    func allPending() -> [UUID]

    /// Record a tombstone for a ride id. Recording the same id twice is a
    /// harmless no-op (the store is a set).
    func add(_ id: UUID)

    /// Remove a tombstone once its remote deletion has succeeded. Removing an
    /// absent id is a harmless no-op.
    func remove(_ id: UUID)
}
