import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for `SwiftDataClipRepository` (rear-camera spec task 15; Requirement 8).
///
/// Most cases use an in-memory `ModelContainer`. Three contracts get explicit
/// coverage from the task: the container-retention rule (a repo built from a
/// dropped container's `mainContext` still works), the corrupt-record skip, and
/// the regression that adding `ClipRecordEntity` to the **shared** container
/// (alongside `RideRecord` and `CrashAlertRecordEntity`) does not disturb
/// existing ride data.
///
/// `@MainActor` because the repository and `ModelContext` are main-actor here.
@MainActor
struct SwiftDataClipRepositoryTests {
    private static let rideA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private static let rideB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)
    private static let t2 = Date(timeIntervalSince1970: 3_000)

    private static func clip(
        _ id: UUID = UUID(),
        ride: UUID,
        createdAt: Date,
        reasons: Set<ClipReason> = [.manual],
        bytes: Int64 = 16_000_000,
        state: ClipState = .saved,
        expiresAt: Date = t2.addingTimeInterval(30 * 24 * 60 * 60)
    ) -> ClipRecord {
        ClipRecord(
            id: id,
            rideId: ride,
            reasons: reasons,
            createdAt: createdAt,
            start: createdAt,
            end: createdAt.addingTimeInterval(45),
            inOffset: 0,
            outOffset: 45,
            durationSeconds: 45,
            bytes: bytes,
            thumbnailPath: nil,
            hasAudio: false,
            state: state,
            hasGap: false,
            eventRef: nil,
            expiresAt: expiresAt
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipRecordEntity.self, configurations: config)
    }

    // MARK: container lifetime

    @Test func repositoryKeepsItsContainerAliveAfterCallerDropsIt() throws {
        func makeRepoDroppingContainer() throws -> SwiftDataClipRepository {
            let container = try makeInMemoryContainer()
            return SwiftDataClipRepository(context: container.mainContext)
        }
        let repo = try makeRepoDroppingContainer()
        let c = Self.clip(ride: Self.rideA, createdAt: Self.t0)
        try repo.save(c)
        #expect(try repo.clips(rideId: Self.rideA) == [c])
    }

    // MARK: save / get / list

    @Test func saveThenFetchByIDRoundTrips() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        let c = Self.clip(ride: Self.rideA, createdAt: Self.t0, reasons: [.manual, .detection])
        try repo.save(c)
        #expect(try repo.clip(id: c.id) == c)
    }

    @Test func clipsForRideAreMostRecentFirstAndIsolatedByRide() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        let older = Self.clip(ride: Self.rideA, createdAt: Self.t0)
        let newer = Self.clip(ride: Self.rideA, createdAt: Self.t2)
        let other = Self.clip(ride: Self.rideB, createdAt: Self.t1)
        try repo.save(older)
        try repo.save(newer)
        try repo.save(other)
        #expect(try repo.clips(rideId: Self.rideA).map(\.id) == [newer.id, older.id])
        #expect(try repo.clips(rideId: Self.rideB).map(\.id) == [other.id])
    }

    @Test func saveUpsertsExistingID() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        let id = UUID()
        try repo.save(Self.clip(id, ride: Self.rideA, createdAt: Self.t0, state: .pending))
        var updated = Self.clip(id, ride: Self.rideA, createdAt: Self.t0, state: .pending)
        updated.state = .saved
        try repo.save(updated)
        #expect(try repo.clips(rideId: Self.rideA).count == 1)
        #expect(try repo.clip(id: id)?.state == .saved)
    }

    // MARK: delete / cascade / deleteAll

    @Test func deleteRemovesOneClip() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        let c = Self.clip(ride: Self.rideA, createdAt: Self.t0)
        try repo.save(c)
        try repo.delete(id: c.id)
        #expect(try repo.clip(id: c.id) == nil)
    }

    @Test func deleteMissingIdIsSafeNoOp() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        try repo.save(Self.clip(ride: Self.rideA, createdAt: Self.t0))
        try repo.delete(id: UUID())
        #expect(try repo.clips(rideId: Self.rideA).count == 1)
    }

    @Test func deleteAllForRideCascadesOnlyThatRide() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        try repo.save(Self.clip(ride: Self.rideA, createdAt: Self.t0))
        try repo.save(Self.clip(ride: Self.rideA, createdAt: Self.t1))
        try repo.save(Self.clip(ride: Self.rideB, createdAt: Self.t2))
        try repo.deleteAll(rideId: Self.rideA)
        #expect(try repo.clips(rideId: Self.rideA).isEmpty)
        #expect(try repo.clips(rideId: Self.rideB).count == 1)
    }

    @Test func deleteAllWipesEverything() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        try repo.save(Self.clip(ride: Self.rideA, createdAt: Self.t0))
        try repo.save(Self.clip(ride: Self.rideB, createdAt: Self.t1))
        try repo.deleteAll()
        #expect(try repo.clips(rideId: Self.rideA).isEmpty)
        #expect(try repo.clips(rideId: Self.rideB).isEmpty)
    }

    // MARK: retention / bytes

    @Test func expiredReturnsClipsAtOrBeforeNow() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        let expired = Self.clip(ride: Self.rideA, createdAt: Self.t0, expiresAt: Self.t1)
        let live = Self.clip(ride: Self.rideA, createdAt: Self.t1, expiresAt: Self.t2.addingTimeInterval(1_000_000))
        try repo.save(expired)
        try repo.save(live)
        let swept = try repo.expired(now: Self.t1)
        #expect(swept.map(\.id) == [expired.id])
    }

    @Test func totalBytesSumsAllClips() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataClipRepository(context: ModelContext(container))
        try repo.save(Self.clip(ride: Self.rideA, createdAt: Self.t0, bytes: 100))
        try repo.save(Self.clip(ride: Self.rideB, createdAt: Self.t1, bytes: 250))
        #expect(try repo.totalBytes() == 350)
    }

    // MARK: corrupt-record skip

    @Test func corruptRecordIsSkippedNotThrown() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repo = SwiftDataClipRepository(context: context)
        let valid = Self.clip(ride: Self.rideA, createdAt: Self.t1)
        try repo.save(valid)

        context.insert(
            ClipRecordEntity(
                id: UUID(),
                rideId: Self.rideA,
                createdAt: Self.t0,
                expiresAt: Self.t2,
                encodedRecord: Data([0x00, 0x01, 0x02]) // not valid JSON
            )
        )
        try context.save()

        #expect(try repo.clips(rideId: Self.rideA).map(\.id) == [valid.id])
    }

    // MARK: permanence across reload (file-backed temporary store)

    @Test func dataPersistsAcrossContainerReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-clip-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }
        let c = Self.clip(ride: Self.rideA, createdAt: Self.t0)

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: ClipRecordEntity.self, configurations: config)
            let repo = SwiftDataClipRepository(context: ModelContext(container))
            try repo.save(c)
        }
        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: ClipRecordEntity.self, configurations: config)
            let repo = SwiftDataClipRepository(context: ModelContext(container))
            #expect(try repo.clip(id: c.id) == c)
        }
    }

    // MARK: regression — adding ClipRecordEntity to the shared container

    @Test func addingClipEntityToSharedContainerLeavesRideDataIntact() throws {
        // The live app shares one container across RideRecord,
        // CrashAlertRecordEntity, and (now) ClipRecordEntity. Adding the new
        // @Model must not disturb existing ride data.
        let schema: [any PersistentModel.Type] = [
            RideRecord.self, CrashAlertRecordEntity.self, ClipRecordEntity.self
        ]
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(schema), configurations: config)
        let context = container.mainContext

        // A ride saved via the ride repository is readable, and a clip saved
        // via the clip repository on the same context coexists without touching
        // the ride.
        let rideRepo = SwiftDataRideRepository(context: context)
        let ride = Ride(
            id: Self.rideA,
            startedAt: Self.t0,
            endedAt: Self.t1,
            points: [],
            summary: RideSummary(distanceMeters: 100, activeDuration: 60, averageSpeedMetersPerSecond: 1.67)
        )
        try rideRepo.save(ride)

        let clipRepo = SwiftDataClipRepository(context: context)
        try clipRepo.save(Self.clip(ride: Self.rideA, createdAt: Self.t1))

        #expect(try rideRepo.ride(id: Self.rideA) == ride)
        #expect(try rideRepo.allRides().count == 1)
        #expect(try clipRepo.clips(rideId: Self.rideA).count == 1)
    }

    // MARK: helpers

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: url.path + suffix)
        }
    }
}
