import Foundation
import Testing
@testable import Whoosh

/// Shared test fixtures for crash-alert records, used by both the in-memory and
/// SwiftData repository tests so the two implementations are exercised against
/// the same shapes.
enum CrashRecordFixture {
    static func location() -> LocationSnapshot {
        LocationSnapshot(
            latitude: 42.36012,
            longitude: -71.05888,
            horizontalAccuracy: 12,
            fixTime: Date(timeIntervalSince1970: 1_000),
            status: .current
        )
    }

    static func event(
        id: UUID = UUID(),
        detectedAt: Date,
        state: CrashEventState = .sent,
        isDrill: Bool = false
    ) -> CrashEvent {
        CrashEvent(
            id: id,
            detectedAt: detectedAt,
            utcOffsetMinutes: -240,
            isDrill: isDrill,
            source: "simulator",
            confidence: 0.9,
            rideId: nil,
            state: state,
            countdown: nil,
            suppressedUntil: nil,
            locationAtDetection: location(),
            footageRef: nil,
            outcome: .expired
        )
    }

    static func attempt(
        recipientRef: UUID = UUID(),
        maskedNumber: String = "23",
        status: AttemptStatus = .sent
    ) -> AlertAttempt {
        AlertAttempt(
            recipientRef: recipientRef,
            labelSnapshot: "Mom",
            maskedNumber: maskedNumber,
            kind: .crashAlert,
            status: status,
            attemptedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    static func record(
        id: UUID = UUID(),
        detectedAt: Date,
        state: CrashEventState = .sent,
        renderedText: String = "WHOOSH ALERT: Alex ...",
        attempts: [AlertAttempt]? = nil
    ) -> CrashAlertRecord {
        let event = event(id: id, detectedAt: detectedAt, state: state)
        return CrashAlertRecord(
            event: event,
            locationAtSend: nil,
            templateVersion: 1,
            renderedText: renderedText,
            attempts: attempts ?? [attempt()],
            createdAt: detectedAt,
            updatedAt: detectedAt
        )
    }
}

/// Tests for the in-memory `CrashAlertRepository` (crash-response task 9,
/// Requirements 11.1, 11.5, 11.9). The same behavioral contract is expected of
/// `SwiftDataCrashAlertRepository` (see `SwiftDataCrashAlertRepositoryTests`).
@MainActor
struct InMemoryCrashAlertRepositoryTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)
    private static let t1 = Date(timeIntervalSince1970: 2_000)
    private static let t2 = Date(timeIntervalSince1970: 3_000)

    @Test func saveThenGetByID() throws {
        let repo = InMemoryCrashAlertRepository()
        let record = CrashRecordFixture.record(detectedAt: Self.t0)
        try repo.save(record)
        #expect(try repo.record(id: record.id) == record)
    }

    @Test func getMissingIDReturnsNil() throws {
        let repo = InMemoryCrashAlertRepository()
        #expect(try repo.record(id: UUID()) == nil)
    }

    @Test func allIsMostRecentFirst() throws {
        let repo = InMemoryCrashAlertRepository()
        let oldest = CrashRecordFixture.record(detectedAt: Self.t0)
        let middle = CrashRecordFixture.record(detectedAt: Self.t1)
        let newest = CrashRecordFixture.record(detectedAt: Self.t2)
        try repo.save(middle)
        try repo.save(oldest)
        try repo.save(newest)
        #expect(try repo.all().map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func saveUpsertsExistingID() throws {
        let repo = InMemoryCrashAlertRepository()
        let id = UUID()
        try repo.save(CrashRecordFixture.record(id: id, detectedAt: Self.t0, renderedText: "v1"))
        try repo.save(CrashRecordFixture.record(id: id, detectedAt: Self.t0, renderedText: "v2"))
        #expect(try repo.all().count == 1)
        #expect(try repo.record(id: id)?.renderedText == "v2")
    }

    @Test func deleteRemovesPermanently() throws {
        let repo = InMemoryCrashAlertRepository()
        let record = CrashRecordFixture.record(detectedAt: Self.t0)
        try repo.save(record)
        try repo.delete(id: record.id)
        #expect(try repo.record(id: record.id) == nil)
        #expect(try repo.all().isEmpty)
    }

    @Test func deleteMissingIDIsSafeNoOp() throws {
        let repo = InMemoryCrashAlertRepository()
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0))
        try repo.delete(id: UUID())
        #expect(try repo.all().count == 1)
    }

    @Test func deleteAllWipesEverything() throws {
        let repo = InMemoryCrashAlertRepository()
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t1))
        try repo.deleteAll()
        #expect(try repo.all().isEmpty)
    }

    // MARK: purge (Requirement 11.9)

    @Test func purgeRemovesOnlyOlderThanCutoff() throws {
        let repo = InMemoryCrashAlertRepository()
        let old = CrashRecordFixture.record(detectedAt: Self.t0)
        let keep = CrashRecordFixture.record(detectedAt: Self.t2)
        try repo.save(old)
        try repo.save(keep)
        try repo.purge(olderThan: Self.t1)
        #expect(try repo.all().map(\.id) == [keep.id])
    }

    @Test func purgeKeepsRecordExactlyAtCutoff() throws {
        let repo = InMemoryCrashAlertRepository()
        let boundary = CrashRecordFixture.record(detectedAt: Self.t1)
        try repo.save(boundary)
        // Cutoff equal to the record's time keeps it (purge is strictly older).
        try repo.purge(olderThan: Self.t1)
        #expect(try repo.all().count == 1)
    }

    // MARK: active event (Requirement 13.5)

    @Test func activeEventReturnsNonRestingRecord() throws {
        let repo = InMemoryCrashAlertRepository()
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0, state: .sent))
        let active = CrashRecordFixture.record(detectedAt: Self.t1, state: .countdown)
        try repo.save(active)
        #expect(try repo.activeEvent()?.id == active.id)
    }

    @Test func activeEventIsNilWhenAllResting() throws {
        let repo = InMemoryCrashAlertRepository()
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t0, state: .sent))
        try repo.save(CrashRecordFixture.record(detectedAt: Self.t1, state: .cancelled))
        #expect(try repo.activeEvent() == nil)
    }
}
