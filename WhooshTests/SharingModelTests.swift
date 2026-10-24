import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for task 28c: the `setSharing` seam, the `sharePublicly` ride field,
/// and the new `.failed` sync status (Requirements 12.11, 12.13, 12.15, 12.22).
@MainActor
struct SharingModelTests {
    private static func ride(
        _ id: UUID = UUID(),
        sharePublicly: Bool = false,
        syncStatus: SyncStatus = .localOnly
    ) -> Ride {
        Ride(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_600),
            points: [],
            summary: .zero,
            sharePublicly: sharePublicly,
            syncStatus: syncStatus
        )
    }

    // MARK: setSharing on the fake / noop

    @Test func fakeRecordsSetSharingCalls() async throws {
        let service = FakeRideSyncService()
        let id = UUID()

        try await service.setSharing(id: id, shared: true)
        try await service.setSharing(id: id, shared: false)

        #expect(service.setSharingCalls == [.init(id: id, shared: true),
                                            .init(id: id, shared: false)])
    }

    @Test func noopSetSharingIsAHarmlessNoOp() async throws {
        let service = NoopRideSyncService()
        // Must not throw and has no observable effect.
        try await service.setSharing(id: UUID(), shared: true)
    }

    // MARK: sharePublicly defaults

    @Test func newRidesDefaultToNotShared() {
        let ride = Ride(startedAt: Date())
        #expect(ride.sharePublicly == false)
    }

    // MARK: .failed sync status

    @Test func failedStatusHasATitle() {
        #expect(SyncStatus.failed.title == "Failed")
    }

    @Test func failedStatusRoundTripsThroughPersistence() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RideRecord.self, configurations: config)
        let repo = SwiftDataRideRepository(context: container.mainContext)

        let ride = Self.ride(sharePublicly: true, syncStatus: .failed)
        try repo.save(ride)

        let loaded = try #require(try repo.ride(id: ride.id))
        #expect(loaded.syncStatus == .failed)
        #expect(loaded.sharePublicly == true)
    }

    @Test func sharePubliclyRoundTripsThroughInMemoryRepository() throws {
        let repo = InMemoryRideRepository()
        let ride = Self.ride(sharePublicly: true, syncStatus: .synced)
        try repo.save(ride)

        let loaded = try #require(try repo.ride(id: ride.id))
        #expect(loaded.sharePublicly == true)
        #expect(loaded.syncStatus == .synced)
    }
}
