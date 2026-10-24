import Foundation
import Testing
@testable import Whoosh

/// Tests for `CrashAlertLogViewModel` (crash-response task 22, Requirements
/// 11.5, 11.9). Ordering, single/all deletion (real deletion), and retention
/// purge on load are verified with the in-memory repository and a `TestClock`.
@MainActor
struct CrashAlertLogViewModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000) // oldest
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000) // newest

    private func makeViewModel(
        records: [CrashAlertRecord] = [],
        now: Date = Date(timeIntervalSince1970: 3_000_000),
        retention: TimeInterval = CrashResponseTuning().localRecordRetention
    ) -> (CrashAlertLogViewModel, InMemoryCrashAlertRepository) {
        let repo = InMemoryCrashAlertRepository(records: records)
        let vm = CrashAlertLogViewModel(
            repository: repo,
            clock: TestClock(now: now),
            retention: retention
        )
        return (vm, repo)
    }

    // MARK: - Ordering (Requirement 11.5)

    @Test func recordsAreMostRecentFirst() {
        let r0 = CrashRecordFixture.record(detectedAt: t0)
        let r1 = CrashRecordFixture.record(detectedAt: t1)
        let r2 = CrashRecordFixture.record(detectedAt: t2)
        // Insert out of order.
        let (vm, _) = makeViewModel(records: [r1, r0, r2])
        #expect(vm.records.map(\.event.detectedAt) == [t2, t1, t0])
    }

    @Test func emptyWhenNoRecords() {
        let (vm, _) = makeViewModel()
        #expect(vm.isEmpty)
        #expect(vm.records.isEmpty)
    }

    // MARK: - Delete one (Requirement 11.5)

    @Test func deleteOneRemovesOnlyThatRecord() throws {
        let r0 = CrashRecordFixture.record(detectedAt: t0)
        let r1 = CrashRecordFixture.record(detectedAt: t1)
        let (vm, repo) = makeViewModel(records: [r0, r1])
        vm.delete(id: r0.id)
        #expect(vm.records.map(\.id) == [r1.id])
        // Real deletion in the backing store.
        #expect(try repo.record(id: r0.id) == nil)
        #expect(try repo.record(id: r1.id) != nil)
    }

    @Test func deleteMissingIDIsSafe() {
        let r0 = CrashRecordFixture.record(detectedAt: t0)
        let (vm, _) = makeViewModel(records: [r0])
        vm.delete(id: UUID())
        #expect(vm.records.count == 1)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Delete all (Requirement 11.5)

    @Test func deleteAllRemovesEverything() throws {
        let (vm, repo) = makeViewModel(records: [
            CrashRecordFixture.record(detectedAt: t0),
            CrashRecordFixture.record(detectedAt: t1),
            CrashRecordFixture.record(detectedAt: t2),
        ])
        vm.deleteAll()
        #expect(vm.records.isEmpty)
        #expect(vm.isEmpty)
        #expect(try repo.all().isEmpty)
    }

    // MARK: - Retention purge (Requirement 11.9)

    @Test func loadPurgesRecordsOlderThanRetention() throws {
        // Retention = 1 day; now = t2. t0 and t1 are far older than a day; make
        // a fresh record just under the window.
        let retention: TimeInterval = 24 * 60 * 60
        let recent = CrashRecordFixture.record(detectedAt: t2.addingTimeInterval(-60))
        let old0 = CrashRecordFixture.record(detectedAt: t0)
        let old1 = CrashRecordFixture.record(detectedAt: t1)
        let (vm, repo) = makeViewModel(
            records: [recent, old0, old1],
            now: t2,
            retention: retention
        )
        // On init → load → purge: only the recent record survives.
        #expect(vm.records.map(\.id) == [recent.id])
        #expect(try repo.record(id: old0.id) == nil)
        #expect(try repo.record(id: old1.id) == nil)
    }

    @Test func loadKeepsRecordsWithinRetention() {
        let retention: TimeInterval = 90 * 24 * 60 * 60
        let (vm, _) = makeViewModel(
            records: [
                CrashRecordFixture.record(detectedAt: t1),
                CrashRecordFixture.record(detectedAt: t2),
            ],
            now: t2,
            retention: retention
        )
        #expect(vm.records.count == 2)
    }

    // MARK: - Reload

    @Test func reloadPicksUpNewRecords() throws {
        let (vm, repo) = makeViewModel()
        #expect(vm.isEmpty)
        try repo.save(CrashRecordFixture.record(detectedAt: t2))
        vm.load()
        #expect(vm.records.count == 1)
    }
}
