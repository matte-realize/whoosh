import Foundation
@testable import Whoosh

/// Scriptable `RideSyncService` fake for `SyncCoordinator` tests.
///
/// Records every `upload`/`deleteRemote` call (so tests can assert ordering and
/// the absence of duplicates) and can be scripted to fail a configurable number
/// of upcoming calls, modelling an offline device that later reconnects.
///
/// `@MainActor` because the `SyncCoordinator` under test is main-actor isolated;
/// keeping the fake on the same actor lets its mutable counters be touched
/// without data-race warnings.
@MainActor
final class FakeRideSyncService: RideSyncService {
    struct SyncError: Error {}

    var isEnabled: Bool

    /// Ride ids passed to `upload`, in call order (duplicates included).
    private(set) var uploadedIDs: [UUID] = []
    /// Full rides passed to `upload`, in call order (to inspect trimmed points).
    private(set) var uploadedRides: [Ride] = []
    /// Ride ids passed to `deleteRemote`, in call order.
    private(set) var deletedIDs: [UUID] = []

    /// Number of upcoming `upload` calls that should throw before succeeding.
    var uploadFailuresRemaining: Int
    /// Number of upcoming `deleteRemote` calls that should throw before succeeding.
    var deleteFailuresRemaining: Int

    init(
        isEnabled: Bool = true,
        uploadFailuresRemaining: Int = 0,
        deleteFailuresRemaining: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.uploadFailuresRemaining = uploadFailuresRemaining
        self.deleteFailuresRemaining = deleteFailuresRemaining
    }

    func upload(_ ride: Ride) async throws {
        if uploadFailuresRemaining > 0 {
            uploadFailuresRemaining -= 1
            throw SyncError()
        }
        uploadedIDs.append(ride.id)
        uploadedRides.append(ride)
    }

    func deleteRemote(id: UUID) async throws {
        if deleteFailuresRemaining > 0 {
            deleteFailuresRemaining -= 1
            throw SyncError()
        }
        deletedIDs.append(id)
    }
}
