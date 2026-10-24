import Foundation
import Testing
@testable import Whoosh

/// Tests for the task 7 seams: `CrashDetector` (Noop + Fake), `FootageBuffer`
/// (Noop + Fake), and the read-only `RideContext` fake. They verify the fakes
/// behave as scripted and that the Noop implementations do nothing.
@MainActor
struct CrashDetectorSeamTests {

    // MARK: NoopCrashDetector

    @Test func noopDetectorNeverEmits() {
        let detector = NoopCrashDetector()
        var signals: [CrashSignal] = []
        detector.onSignal = { signals.append($0) }
        detector.start()
        detector.stop()
        #expect(signals.isEmpty)
    }

    // MARK: FakeCrashDetector

    @Test func fakeDetectorDeliversOnlyWhileMonitoring() {
        let detector = FakeCrashDetector()
        var delivered: [CrashSignal] = []
        detector.onSignal = { delivered.append($0) }

        // Not started yet: recorded but not delivered.
        detector.emit(confidence: 0.9, source: "motion")
        #expect(delivered.isEmpty)
        #expect(detector.emitted.count == 1)

        detector.start()
        detector.emit(confidence: 1.0, source: "simulator")
        #expect(delivered.count == 1)
        #expect(delivered.first?.confidence == 1.0)
        #expect(delivered.first?.source == "simulator")

        detector.stop()
        detector.emit()
        #expect(delivered.count == 1) // stopped: not delivered
        #expect(detector.delivered.count == 1)
    }

    @Test func fakeDetectorRecordsStartStopCounts() {
        let detector = FakeCrashDetector()
        #expect(!detector.isMonitoring)
        detector.start()
        #expect(detector.isMonitoring)
        detector.start()
        detector.stop()
        #expect(!detector.isMonitoring)
        #expect(detector.startCount == 2)
        #expect(detector.stopCount == 1)
    }

    @Test func fakeDetectorEmitDrillCarriesDrillFlag() {
        let detector = FakeCrashDetector()
        detector.start()
        var delivered: [CrashSignal] = []
        detector.onSignal = { delivered.append($0) }
        let signal = detector.emitDrill()
        #expect(signal.isDrill)
        #expect(signal.confidence == 1.0)
        #expect(delivered.first?.isDrill == true)
    }

    @Test func fakeDetectorUsesDefaultTimestamp() {
        let fixed = Date(timeIntervalSince1970: 1_000)
        let detector = FakeCrashDetector(defaultTimestamp: fixed)
        detector.start()
        let signal = detector.emit()
        #expect(signal.timestamp == fixed)
    }
}

@MainActor
struct FootageBufferSeamTests {

    @Test func noopFootageBufferReturnsNoReference() {
        let buffer = NoopFootageBuffer()
        #expect(buffer.preserve(eventId: UUID(), around: Date()) == nil)
        buffer.delete(reference: "anything") // no crash
    }

    @Test func fakeFootageBufferRecordsPreserveCalls() {
        let buffer = FakeFootageBuffer(referenceToReturn: "local-ref-1")
        let id = UUID()
        let when = Date(timeIntervalSince1970: 42)
        let ref = buffer.preserve(eventId: id, around: when)
        #expect(ref == "local-ref-1")
        #expect(buffer.preserveCalls.count == 1)
        #expect(buffer.preserveCalls.first?.eventId == id)
        #expect(buffer.preserveCalls.first?.detectedAt == when)
    }

    @Test func fakeFootageBufferDefaultsToNoReference() {
        let buffer = FakeFootageBuffer()
        #expect(buffer.preserve(eventId: UUID(), around: Date()) == nil)
    }

    @Test func fakeFootageBufferRecordsDeletions() {
        let buffer = FakeFootageBuffer()
        buffer.delete(reference: "r1")
        buffer.delete(reference: "r2")
        #expect(buffer.deletedReferences == ["r1", "r2"])
    }
}

@MainActor
struct RideContextSeamTests {

    @Test func fakeRideContextDefaultsAreInactive() {
        let context = FakeRideContext()
        #expect(!context.isRideActive)
        #expect(!context.isRecordingOrSignalLost)
        #expect(context.latestAcceptedFix == nil)
        #expect(context.currentRideID == nil)
    }

    @Test func fakeRideContextExposesScriptedState() {
        let fix = RideFix(latitude: 42.36, longitude: -71.06, horizontalAccuracy: 12, timestamp: Date(timeIntervalSince1970: 100))
        let id = UUID()
        let context = FakeRideContext(
            isRideActive: true,
            isRecordingOrSignalLost: true,
            latestAcceptedFix: fix,
            currentRideID: id
        )
        #expect(context.isRideActive)
        #expect(context.isRecordingOrSignalLost)
        #expect(context.latestAcceptedFix == fix)
        #expect(context.currentRideID == id)
    }
}
