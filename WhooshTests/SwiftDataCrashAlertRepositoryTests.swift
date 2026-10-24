import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for the SwiftData crash-alert repository (crash-response task 10,
/// Requirements 11.1, 11.3, 11.5, 11.9).
///
/// Most cases use an in-memory `ModelContainer`; permanence "across reload"
/// uses a file-backed temporary store opened by two separate containers. One
/// case asserts the repository keeps its container alive after the caller drops
/// it (the lesson from `SwiftDataRideRepository`). Reuses `CrashRecordFixture`.
@MainActor
struct SwiftDataCrashAlertRepositoryTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)
    private static let t2 = Date(timeIntervalSince1970: 3_000)

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: CrashAlertRecordEntity.self, configurations: config)
    }

    /// Builds a repository the way the composition root does: the container is a
    /// local that goes out of scope, and only its `mainContext` is kept.
    private func makeRepositoryDroppingContainer() throws -> SwiftDataCrashAlertRepository {
        let container = try makeInMemoryContainer()
        return SwiftDataCrashAlertRepository(context: container.mainContext)
    }

    // MARK: container lifetime

    @Test func repositoryKeepsItsContainerAliveAfterCallerDropsIt() throws {
        let repo = try makeRepositoryDroppingContainer()
        let record = CrashRecordFixture.record(detectedAt: Self.t0)
        try repo.save(record)
        #expect(try repo.all() == [record])
    }

    // MARK: save / get / list

    @Test func saveThenGetByIDRoundTrips() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        let record = CrashRecordFixture.record(detectedAt: Self.t0)
        try repo.save(record)
        #expect(try repo.record(id: record.id) == record)
    }

    @Test func getMissingIDReturnsNil() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        #expect(try repo.record(id: UUID()) == nil)
    }

    @Test func allIsMostRecentFirst() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        let oldest = CrashRecordFixture.record(detectedAt: Self.t0)
        let middle = CrashRecordFixture.record(detectedAt: Self.t1)
        let newest = CrashRecordFixture.record(detectedAt: Self.t2)
        try repo.save(middle)
        try repo.save(oldest)
        try repo.save(newest)
        #expect(try repo.all().map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func saveUpsertsExistingID() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        let id = UUID()
        try repo.save(CrashRecordFixture.record(id: id, detectedAt: Self.t0, renderedText: "v1"))
        try repo.save(CrashRecordFixture.record(id: id, detectedAt: Self.t0, renderedText: "v2"))
        #expect(try repo.all().count == 1)
        #expect(try repo.record(id: id)?.renderedText == "v2")
    }

    // MARK: delete / deleteAll

    @Test func deleteRemovesPermanently() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        let record = CrashRecordFixture.record(detectedAt: Self.t0)
        try repo.save(record)
        try repo.delete(id: record.id)
        #expect(try repo.record(id: record.id) == nil)
        #expect(try repo.all().isEmpty)
    }

    @Test func deleteMissingIDIsSafeNoOp() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0))
        try repo.delete(id: UUID())
        #expect(try repo.all().count == 1)
    }

    @Test func deleteAllWipesEverything() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t1))
        try repo.deleteAll()
        #expect(try repo.all().isEmpty)
    }

    // MARK: purge (Requirement 11.9)

    @Test func purgeRemovesOnlyOlderThanCutoff() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        let old = CrashRecordFixture.record(detectedAt: Self.t0)
        let keep = CrashRecordFixture.record(detectedAt: Self.t2)
        try repo.save(old)
        try repo.save(keep)
        try repo.purge(olderThan: Self.t1)
        #expect(try repo.all().map(\.id) == [keep.id])
    }

    // MARK: active event (Requirement 13.5)

    @Test func activeEventReturnsNonRestingRecord() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0, state: .sent))
        let active = CrashRecordFixture.record(detectedAt: Self.t1, state: .countdown)
        try repo.save(active)
        #expect(try repo.activeEvent()?.id == active.id)
    }

    @Test func activeEventIsNilWhenAllResting() throws {
        let container = try makeInMemoryContainer()
        let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0, state: .sent))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t1, state: .cancelled))
        #expect(try repo.activeEvent() == nil)
    }

    // MARK: permanence across reload (file-backed temporary store)

    @Test func dataPersistsAcrossContainerReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-crash-test-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }

        let record = CrashRecordFixture.record(detectedAt: Self.t0)

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: CrashAlertRecordEntity.self, configurations: config)
            let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
            try repo.save(record)
        }

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: CrashAlertRecordEntity.self, configurations: config)
            let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
            #expect(try repo.record(id: record.id) == record)
        }
    }

    @Test func deletionPersistsAcrossContainerReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-crash-test-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: url) }

        let record = CrashRecordFixture.record(detectedAt: Self.t0)

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: CrashAlertRecordEntity.self, configurations: config)
            let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
            try repo.save(record)
            try repo.delete(id: record.id)
        }

        do {
            let config = ModelConfiguration(url: url)
            let container = try ModelContainer(for: CrashAlertRecordEntity.self, configurations: config)
            let repo = SwiftDataCrashAlertRepository(context: ModelContext(container))
            #expect(try repo.all().isEmpty)
        }
    }

    // MARK: corrupt-record skip

    @Test func corruptRecordIsSkippedNotThrown() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repo = SwiftDataCrashAlertRepository(context: context)

        let valid = CrashRecordFixture.record(detectedAt: Self.t1)
        try repo.save(valid)

        let corrupt = CrashAlertRecordEntity(
            id: UUID(),
            detectedAt: Self.t0,
            stateRaw: CrashEventState.sent.rawValue,
            encodedRecord: Data([0x00, 0x01, 0x02]) // not valid JSON
        )
        context.insert(corrupt)
        try context.save()

        #expect(try repo.all().map(\.id) == [valid.id])
    }

    // MARK: no full phone number stored (Requirement 11.3)

    @Test func noFullPhoneNumberInAnyStoredField() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let repo = SwiftDataCrashAlertRepository(context: context)

        // A record whose attempt carries only the masked last-2-digits, and a
        // rendered text that does not contain the full number.
        let record = CrashRecordFixture.record(
            detectedAt: Self.t0,
            renderedText: "WHOOSH ALERT: Alex may have crashed."
        )
        try repo.save(record)

        // Inspect the raw stored blob: the full number must appear nowhere.
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>()
        let entities = try context.fetch(descriptor)
        #expect(entities.count == 1)
        let blob = String(decoding: entities[0].encodedRecord, as: UTF8.self)
        let fullNumber = "+16175550123"
        #expect(!blob.contains(fullNumber))
        // The masked last-2-digits is present.
        #expect(record.attempts.first?.maskedNumber == "23")
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
