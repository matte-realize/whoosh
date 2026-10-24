import Foundation
import Testing
@testable import Whoosh

/// Tests for the in-memory fake repository (Requirements 7.2, 7.4, 7.5, 7.8).
/// The same behavioral contract is expected of `SwiftDataRideRepository`.
struct InMemoryRideRepositoryTests {
    private static func ride(
        _ id: UUID = UUID(),
        startedAt: Date
    ) -> Ride {
        Ride(id: id, startedAt: startedAt)
    }

    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)
    private static let t2 = Date(timeIntervalSince1970: 3_000)

    @Test func saveThenFetchByID() throws {
        let repo = InMemoryRideRepository()
        let ride = Self.ride(startedAt: Self.t0)
        try repo.save(ride)
        #expect(try repo.ride(id: ride.id) == ride)
    }

    @Test func fetchMissingIDReturnsNil() throws {
        let repo = InMemoryRideRepository()
        #expect(try repo.ride(id: UUID()) == nil)
    }

    @Test func allRidesIsMostRecentFirst() throws {
        let repo = InMemoryRideRepository()
        let oldest = Self.ride(startedAt: Self.t0)
        let middle = Self.ride(startedAt: Self.t1)
        let newest = Self.ride(startedAt: Self.t2)
        // Insert out of order to prove sorting, not insertion order.
        try repo.save(middle)
        try repo.save(oldest)
        try repo.save(newest)

        let all = try repo.allRides()
        #expect(all.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func saveUpsertsExistingID() throws {
        let repo = InMemoryRideRepository()
        let id = UUID()
        try repo.save(Self.ride(id, startedAt: Self.t0))
        var updated = Self.ride(id, startedAt: Self.t0)
        updated.endedAt = Self.t1
        try repo.save(updated)

        #expect(try repo.allRides().count == 1)
        #expect(try repo.ride(id: id)?.endedAt == Self.t1)
    }

    @Test func deleteRemovesPermanently() throws {
        let repo = InMemoryRideRepository()
        let ride = Self.ride(startedAt: Self.t0)
        try repo.save(ride)
        try repo.delete(id: ride.id)
        #expect(try repo.ride(id: ride.id) == nil)
        #expect(try repo.allRides().isEmpty)
    }

    @Test func deleteMissingIDIsSafeNoOp() throws {
        let repo = InMemoryRideRepository()
        let ride = Self.ride(startedAt: Self.t0)
        try repo.save(ride)
        // Deleting an id that was never stored must not throw or remove anything.
        try repo.delete(id: UUID())
        #expect(try repo.allRides().count == 1)
    }

    @Test func deleteAllWipesEverything() throws {
        let repo = InMemoryRideRepository()
        try repo.save(Self.ride(startedAt: Self.t0))
        try repo.save(Self.ride(startedAt: Self.t1))
        try repo.save(Self.ride(startedAt: Self.t2))

        try repo.deleteAll()
        #expect(try repo.allRides().isEmpty)
    }

    @Test func deleteAllOnEmptyRepositoryIsSafe() throws {
        let repo = InMemoryRideRepository()
        try repo.deleteAll()
        #expect(try repo.allRides().isEmpty)
    }
}
