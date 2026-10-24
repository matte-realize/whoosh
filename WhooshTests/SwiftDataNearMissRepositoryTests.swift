import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for `SwiftDataNearMissRepository` (rear-camera task 28).
///
/// Builds the same shared-container shape as `AppEnvironment.makeLiveRepositories()`
/// (one in-memory container holding `RideRecord`, `CrashAlertRecordEntity`, and
/// `NearMissEventEntity`) to confirm the new `@Model` coexists with the shipped
/// ride model and that per-ride fetch is oldest-first.
@MainActor
struct SwiftDataNearMissRepositoryTests {
    /// Keeps every container alive for the test run: a `ModelContext` does not
    /// retain its container, so returning only the context let it be freed
    /// before the repository was built (crashing the test host).
    private static var liveContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let schema: [any PersistentModel.Type] = [
            RideRecord.self,
            CrashAlertRecordEntity.self,
            NearMissEventEntity.self,
        ]
        let container = try ModelContainer(
            for: Schema(schema),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        Self.liveContainers.append(container)
        return container.mainContext
    }

    private func event(rideId: UUID, occurredAt: Date, isDemo: Bool = false) -> NearMissEvent {
        NearMissEvent(
            id: UUID(),
            rideId: rideId,
            occurredAt: occurredAt,
            latitude: 42.36,
            longitude: -71.06,
            kind: "vehicle",
            confidence: 0.8,
            positionHint: "left",
            source: .detected,
            isDemo: isDemo,
            localClipId: UUID() // a local clip id round-trips but never uploads
        )
    }

    @Test func savesAndFetchesOldestFirst() throws {
        let repo = SwiftDataNearMissRepository(context: try makeContext())
        let rideId = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let later = event(rideId: rideId, occurredAt: base.addingTimeInterval(60))
        let earlier = event(rideId: rideId, occurredAt: base)
        try repo.save(later)
        try repo.save(earlier)

        let events = try repo.events(rideId: rideId)
        #expect(events.count == 2)
        #expect(events.first?.id == earlier.id) // oldest first
        #expect(events.first?.localClipId == earlier.localClipId) // round-trips locally
    }

    @Test func deleteAllForRideCascades() throws {
        let repo = SwiftDataNearMissRepository(context: try makeContext())
        let rideA = UUID()
        let rideB = UUID()
        try repo.save(event(rideId: rideA, occurredAt: Date()))
        try repo.save(event(rideId: rideB, occurredAt: Date()))

        try repo.deleteAll(rideId: rideA)

        #expect(try repo.events(rideId: rideA).isEmpty)
        #expect(try repo.events(rideId: rideB).count == 1)
    }

    @Test func ridesCoexistWithNearMissesInSharedContainer() throws {
        let context = try makeContext()
        let rideRepo = SwiftDataRideRepository(context: context)
        let nmRepo = SwiftDataNearMissRepository(context: context)
        let ride = Ride(
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000),
            points: [],
            summary: .zero
        )
        try rideRepo.save(ride)
        try nmRepo.save(event(rideId: ride.id, occurredAt: Date(timeIntervalSince1970: 1_500)))

        // The ride model is untouched by the near-miss entity sharing the store.
        #expect(try rideRepo.ride(id: ride.id) != nil)
        #expect(try nmRepo.events(rideId: ride.id).count == 1)
    }
}
