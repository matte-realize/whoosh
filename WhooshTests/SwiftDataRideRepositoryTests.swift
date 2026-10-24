import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for the SwiftData repository (Requirements 7.1–7.4, 7.6–7.8).
///
/// Most cases use an in-memory `ModelContainer`; permanence "across reload"
/// uses a file-backed temporary store opened by two separate containers.
/// `@MainActor` because `SwiftDataRideRepository` and `ModelContext` are
/// main-actor here.
@MainActor
struct SwiftDataRideRepositoryTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)
    private static let t2 = Date(timeIntervalSince1970: 3_000)

    private static func point(_ lat: Double, _ lon: Double) -> RoutePoint {
        RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: t0,
            speedMetersPerSecond: 5,
            horizontalAccuracyMeters: 5
        )
    }

    private static func ride(
        _ id: UUID = UUID(),
        startedAt: Date,
        points: [RoutePoint] = []
    ) -> Ride {
        Ride(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            points: points,
            summary: RideSummary(
                distanceMeters: 1234,
                activeDuration: 600,
                averageSpeedMetersPerSecond: 2.05
            )
        )
    }

    /// A fresh in-memory container for an isolated test.
    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: RideRecord.self, configurations: config)
    }

    // MARK: save / get / list

    @Test func saveThenFetchByIDRoundTripsPointsAndSummary() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let ride = Self.ride(
            startedAt: Self.t0,
            points: [Self.point(42.0, -71.0), Self.point(42.1, -71.1)]
        )
        try repo.save(ride)

        let fetched = try repo.ride(id: ride.id)
        #expect(fetched == ride)
    }

    @Test func fetchMissingIDReturnsNil() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        #expect(try repo.ride(id: UUID()) == nil)
    }

    @Test func allRidesIsMostRecentFirst() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let oldest = Self.ride(startedAt: Self.t0)
        let middle = Self.ride(startedAt: Self.t1)
        let newest = Self.ride(startedAt: Self.t2)
        try repo.save(middle)
        try repo.save(oldest)
        try repo.save(newest)

        #expect(try repo.allRides().map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func saveUpsertsExistingID() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let id = UUID()
        try repo.save(Self.ride(id, startedAt: Self.t0))
        var updated = Self.ride(id, startedAt: Self.t0)
        updated.endedAt = Self.t2
        try repo.save(updated)

        #expect(try repo.allRides().count == 1)
        #expect(try repo.ride(id: id)?.endedAt == Self.t2)
    }

    // MARK: delete / deleteAll

    @Test func deleteRemovesPermanently() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let ride = Self.ride(startedAt: Self.t0)
        try repo.save(ride)
        try repo.delete(id: ride.id)
        #expect(try repo.ride(id: ride.id) == nil)
        #expect(try repo.allRides().isEmpty)
    }

    @Test func deleteMissingIDIsSafeNoOp() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        try repo.save(Self.ride(startedAt: Self.t0))
        try repo.delete(id: UUID())
        #expect(try repo.allRides().count == 1)
    }

    @Test func deleteAllWipesEverything() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        try repo.save(Self.ride(startedAt: Self.t0))
        try repo.save(Self.ride(startedAt: Self.t1))
        try repo.deleteAll()
        #expect(try repo.allRides().isEmpty)
    }

    // MARK: permanence across reload (file-backed temporary store)

    @Test func dataPersistsAcrossContainerReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-test-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }

        let ride = Self.ride(
            startedAt: Self.t0,
            points: [Self.point(42.0, -71.0)]
        )

        // First container: save.
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: RideRecord.self, configurations: config)
            let repo = SwiftDataRideRepository(context: ModelContext(container))
            try repo.save(ride)
        }

        // Second container over the same file: the ride must still be there.
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: RideRecord.self, configurations: config)
            let repo = SwiftDataRideRepository(context: ModelContext(container))
            #expect(try repo.ride(id: ride.id) == ride)
        }
    }

    @Test func deletionPersistsAcrossContainerReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-test-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }

        let ride = Self.ride(startedAt: Self.t0)

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: RideRecord.self, configurations: config)
            let repo = SwiftDataRideRepository(context: ModelContext(container))
            try repo.save(ride)
            try repo.delete(id: ride.id)
        }

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: RideRecord.self, configurations: config)
            let repo = SwiftDataRideRepository(context: ModelContext(container))
            #expect(try repo.allRides().isEmpty)
        }
    }

    // MARK: corrupt-record skip (Req 7.7)

    @Test func corruptRecordIsSkippedNotThrown() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repo = SwiftDataRideRepository(context: context)

        // A valid ride and a deliberately corrupt record (non-JSON points blob).
        let valid = Self.ride(startedAt: Self.t1, points: [Self.point(42.0, -71.0)])
        try repo.save(valid)

        let corrupt = RideRecord(
            id: UUID(),
            startedAt: Self.t0,
            endedAt: Self.t1,
            distanceMeters: 0,
            activeDuration: 0,
            averageSpeed: 0,
            encodedPoints: Data([0x00, 0x01, 0x02]) // not valid JSON
        )
        context.insert(corrupt)
        try context.save()

        // allRides skips the corrupt one and returns only the valid ride.
        let all = try repo.allRides()
        #expect(all.map(\.id) == [valid.id])
    }

    // MARK: helpers

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            try? fm.removeItem(atPath: path)
        }
    }
}
