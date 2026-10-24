import Foundation
import Testing
@testable import Whoosh

/// Tests for `SyncCoordinator` (Requirements 12.3, 12.4, 12.6).
///
/// `@MainActor` because the coordinator, the fake service, and the repository
/// are all main-actor isolated. Uses `InMemoryRideRepository` and an in-memory
/// tombstone store so every test is deterministic and leaves no state behind.
@MainActor
struct SyncCoordinatorTests {
    /// A finished ride long enough that `RoutePrivacy.trim` keeps an interior,
    /// so uploads carry a non-empty trimmed route.
    private static func ride(
        _ id: UUID = UUID(),
        status: SyncStatus = .localOnly,
        startedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> Ride {
        let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180
        let degPerStep = 100 / metersPerDegreeLon // ~100 m spacing
        let points = (0..<21).map { i in
            RoutePoint(
                latitude: 0,
                longitude: Double(i) * degPerStep,
                timestamp: startedAt.addingTimeInterval(Double(i)),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
        return Ride(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_200),
            points: points,
            summary: RideSummary(
                distanceMeters: 2_000,
                activeDuration: 1_200,
                averageSpeedMetersPerSecond: 1.67
            ),
            syncStatus: status
        )
    }

    private func makeCoordinator(
        service: FakeRideSyncService,
        repository: InMemoryRideRepository = InMemoryRideRepository(),
        deletes: InMemoryPendingRemoteDeleteStore = InMemoryPendingRemoteDeleteStore()
    ) -> (SyncCoordinator, InMemoryRideRepository, InMemoryPendingRemoteDeleteStore) {
        let coordinator = SyncCoordinator(
            service: service,
            repository: repository,
            pendingDeletes: deletes
        )
        return (coordinator, repository, deletes)
    }

    // MARK: finish → upload

    @Test func finishSavesLocallyThenUploadsAndMarksSynced() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo, _) = makeCoordinator(service: service)
        let ride = Self.ride()
        // Local-first: the caller saves before handing the ride to the coordinator.
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)

        #expect(service.uploadedIDs == [ride.id])
        #expect(try repo.ride(id: ride.id)?.syncStatus == .synced)
    }

    @Test func uploadTrimsRouteForPrivacyButLocalStaysComplete() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo, _) = makeCoordinator(service: service)
        let ride = Self.ride()
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)

        // Remote copy is trimmed (fewer points); local copy is untouched.
        let uploaded = try #require(service.uploadedRides.first)
        #expect(uploaded.points.count < ride.points.count)
        #expect(try repo.ride(id: ride.id)?.points.count == ride.points.count)
    }

    @Test func finishMarksPendingWhenUploadFails() async throws {
        let service = FakeRideSyncService(uploadFailuresRemaining: 1)
        let (coordinator, repo, _) = makeCoordinator(service: service)
        let ride = Self.ride()
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)

        #expect(service.uploadedIDs.isEmpty)
        #expect(try repo.ride(id: ride.id)?.syncStatus == .pending)
    }

    // MARK: retry

    @Test func retryUploadsPendingRidesWithoutDuplicates() async throws {
        // First finish fails → pending. Retry succeeds → synced, uploaded once.
        let service = FakeRideSyncService(uploadFailuresRemaining: 1)
        let (coordinator, repo, _) = makeCoordinator(service: service)
        let ride = Self.ride()
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)     // fails → pending
        await coordinator.retryPending()          // succeeds → synced

        #expect(service.uploadedIDs == [ride.id]) // uploaded exactly once
        #expect(try repo.ride(id: ride.id)?.syncStatus == .synced)
    }

    @Test func retryNeverReUploadsASyncedRide() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo, _) = makeCoordinator(service: service)
        let ride = Self.ride()
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)  // synced
        await coordinator.retryPending()       // should do nothing for this ride
        await coordinator.retryPending()

        #expect(service.uploadedIDs == [ride.id]) // still just one upload
    }

    // MARK: deletes

    @Test func deletingSyncedRideRequestsRemoteDeletion() async throws {
        let service = FakeRideSyncService()
        let (coordinator, _, deletes) = makeCoordinator(service: service)
        let ride = Self.ride(status: .synced)

        await coordinator.rideWasDeleted(ride)

        #expect(service.deletedIDs == [ride.id])
        #expect(deletes.allPending().isEmpty) // tombstone cleared on success
    }

    @Test func deletingLocalOnlyRideMakesNoRemoteCall() async throws {
        let service = FakeRideSyncService()
        let (coordinator, _, deletes) = makeCoordinator(service: service)
        let ride = Self.ride(status: .localOnly)

        await coordinator.rideWasDeleted(ride)

        #expect(service.deletedIDs.isEmpty)
        #expect(deletes.allPending().isEmpty)
    }

    @Test func failedDeleteKeepsTombstoneAndPropagatesAfterReconnect() async throws {
        // Offline: delete fails, tombstone kept. Reconnect: retry drains it.
        let service = FakeRideSyncService(deleteFailuresRemaining: 1)
        let (coordinator, _, deletes) = makeCoordinator(service: service)
        let ride = Self.ride(status: .synced)

        await coordinator.rideWasDeleted(ride)     // fails → tombstone kept
        #expect(service.deletedIDs.isEmpty)
        #expect(deletes.allPending() == [ride.id])

        await coordinator.retryPending()           // reconnect → delete succeeds
        #expect(service.deletedIDs == [ride.id])
        #expect(deletes.allPending().isEmpty)
    }

    @Test func deleteAllTombstonesEveryPreviouslySyncedRide() async throws {
        let service = FakeRideSyncService()
        let (coordinator, _, deletes) = makeCoordinator(service: service)
        let syncedA = UUID()
        let syncedB = UUID()

        await coordinator.allRidesWereDeleted(previouslySynced: [syncedA, syncedB])

        #expect(Set(service.deletedIDs) == [syncedA, syncedB])
        #expect(deletes.allPending().isEmpty)
    }

    @Test func deleteAllKeepsTombstonesWhenRemoteDeletesFail() async throws {
        // Both deletes fail; both tombstones must survive for a later retry.
        let service = FakeRideSyncService(deleteFailuresRemaining: 2)
        let (coordinator, _, deletes) = makeCoordinator(service: service)
        let syncedA = UUID()
        let syncedB = UUID()

        await coordinator.allRidesWereDeleted(previouslySynced: [syncedA, syncedB])

        #expect(service.deletedIDs.isEmpty)
        #expect(Set(deletes.allPending()) == [syncedA, syncedB])
    }

    // MARK: disabled

    @Test func disabledServiceMakesZeroCallsAndNoStatusChange() async throws {
        let service = FakeRideSyncService(isEnabled: false)
        let (coordinator, repo, deletes) = makeCoordinator(service: service)
        let ride = Self.ride(status: .synced)
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)
        await coordinator.rideWasDeleted(ride)
        await coordinator.allRidesWereDeleted(previouslySynced: [ride.id])
        await coordinator.retryPending()

        #expect(service.uploadedIDs.isEmpty)
        #expect(service.deletedIDs.isEmpty)
        #expect(deletes.allPending().isEmpty)
        // A pre-existing ride's status is left exactly as it was.
        #expect(try repo.ride(id: ride.id)?.syncStatus == .synced)
    }
}
