import Foundation
import Testing
@testable import Whoosh

/// Tests for the countdown takeover's **coordinator-driven contracts**
/// (crash-response task 20). `CrashCountdownView` is a thin view over the
/// coordinator's read-only state; the behaviours the view depends on
/// (presentation flag, remaining seconds, drill ⇒ hide Call 911, total length
/// for the announcement cadence) are asserted here against the real coordinator
/// composed with fakes. The SwiftUI rendering itself is a device/preview check.
@MainActor
struct CrashCountdownViewTests {
    typealias Fixtures = CrashResponseCoordinatorTests

    @Test func takeoverPresentedDuringCountdown() {
        let h = Fixtures.makeCoordinator()
        #expect(!h.coordinator.isTakeoverPresented)
        h.detector.emit()
        #expect(h.coordinator.eventState == .countdown)
        #expect(h.coordinator.isTakeoverPresented)
    }

    @Test func takeoverDismissedOnCancel() {
        let h = Fixtures.makeCoordinator()
        h.detector.emit()
        #expect(h.coordinator.isTakeoverPresented)
        h.coordinator.riderCancel()
        #expect(!h.coordinator.isTakeoverPresented)
    }

    @Test func remainingSecondsCountsDownFromTotal() {
        let h = Fixtures.makeCoordinator()
        h.detector.emit()
        #expect(h.coordinator.totalCountdownSeconds == 30)
        #expect(h.coordinator.remainingSeconds == 30)
        h.clock.advance(by: 10)
        #expect(h.coordinator.remainingSeconds == 20)
        // Partial seconds round up, so the last second still reads 1.
        h.clock.advance(by: 19.5)
        #expect(h.coordinator.remainingSeconds == 1)
        // At the deadline the expiry fires and the event leaves the countdown.
        h.clock.advance(by: 0.5)
        #expect(h.coordinator.remainingSeconds == nil)
    }

    @Test func remainingSecondsNilWhenNotCountingDown() {
        let h = Fixtures.makeCoordinator()
        #expect(h.coordinator.remainingSeconds == nil)
    }

    @Test func realEventIsNotADrill() {
        // A real event ⇒ Call 911 is shown (view reads `isDrill == false`).
        let h = Fixtures.makeCoordinator()
        h.detector.emit()
        #expect(!h.coordinator.isDrill)
    }

    @Test func drillHidesCallButton() {
        // A drill ⇒ the view hides Call 911 and shows the inert Demo tag.
        let h = Fixtures.makeCoordinator()
        h.detector.emitDrill()
        #expect(h.coordinator.eventState == .countdown)
        #expect(h.coordinator.isDrill)
    }

    @Test func recipientsSurfaceLabelsForTheSentence() {
        let contacts = [
            EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable),
            EmergencyContact(id: UUID(), label: "Sam", e164: "+16175550124", verification: .reachable),
        ]
        let h = Fixtures.makeCoordinator(contacts: contacts)
        h.detector.emit()
        let labels = Set(h.coordinator.recipients.map(\.label))
        #expect(labels == ["Mom", "Sam"])
        // Masked numbers only — never the full E.164 (Requirement 11.3).
        #expect(h.coordinator.recipients.allSatisfy { $0.maskedNumber.count == 2 })
    }
}
