import Foundation

/// The MVP default `RideSyncService`: sync is **off** and every operation is a
/// no-op (Requirement 12.2).
///
/// `isEnabled` is `false`, so a `SyncCoordinator` backed by this service makes
/// no uploads, no deletes, and no retries — the app stays fully offline and no
/// ride data ever leaves the device. The real `SupabaseRideSyncService` (task
/// 28) replaces this once the backend contract is agreed and the Settings
/// toggle is enabled.
///
/// Contains no network code; it exists so the composition root always has a
/// non-optional sync service to inject.
struct NoopRideSyncService: RideSyncService {
    var isEnabled: Bool { false }

    func upload(_ ride: Ride) async throws {
        // Intentionally does nothing: sync is disabled in the MVP.
    }

    func deleteRemote(id: UUID) async throws {
        // Intentionally does nothing: sync is disabled in the MVP.
    }
}
