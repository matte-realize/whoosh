import Foundation
import Testing
@testable import Whoosh

/// Tests for `CrashAlertStatusView`'s **coordinator-driven contracts**
/// (crash-response task 21): which banner shows per state, when the composer
/// fallback is offered, that "I'm OK — cancel alert" applies to the queued
/// state only, and that the composer payload is prefilled by the shared builder
/// with the recipients' full numbers (composer-only). The SwiftUI rendering is
/// a device/preview check. Fakes only.
@MainActor
struct CrashAlertStatusViewTests {
    typealias Fixtures = CrashResponseCoordinatorTests
    static let t0 = Fixtures.t0

    private static func queuedBehavior(_ ref: UUID) -> FakeCrashNotifier.Behavior {
        .success(recipients: [CrashRecipientResult(recipientRef: ref, status: .queued, segments: 4, updatedAt: t0)],
                 deduplicated: false)
    }

    // MARK: - Banner selection per state

    @Test func queuedOfflineBannerAndComposerAndCancel() {
        let h = Fixtures.makeCoordinator(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        #expect(h.coordinator.bannerKind == .queuedOffline)
        // Composer offered + "I'm OK — cancel" applies only to queued.
        #expect(h.coordinator.isComposerFallbackOffered)
    }

    @Test func staleBannerAfterStaleLimit() async {
        let h = Fixtures.makeCoordinator(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        h.clock.advance(by: 31 * 60)
        h.connectivity.setOnline(true)
        await Fixtures.drain()
        #expect(h.coordinator.eventState == .stale)
        #expect(h.coordinator.bannerKind == .stale)
        #expect(h.coordinator.isComposerFallbackOffered)
    }

    @Test func failedBannerOnNonRetryableError() async {
        let h = Fixtures.makeCoordinator()
        h.notifier.sendBehavior = .failure(CrashNotifierError(.serviceDisabled))
        h.detector.emit()
        h.coordinator.sendNow()
        await Fixtures.drain()
        #expect(h.coordinator.eventState == .fallbackPrompted)
        #expect(h.coordinator.bannerKind == .failed)
        #expect(h.coordinator.isComposerFallbackOffered)
    }

    @Test func noBannerWhenSentCleanly() async {
        let ref = UUID()
        let h = Fixtures.makeCoordinator(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)],
            sendBehavior: Self.queuedBehavior(ref)
        )
        h.detector.emit()
        h.coordinator.sendNow()
        await Fixtures.drain()
        #expect(h.coordinator.eventState == .sent)
        #expect(h.coordinator.bannerKind == .none)
    }

    // MARK: - Composer fallback payload (prefilled, composer-only numbers)

    @Test func composerPayloadPrefilledWithBuilderBodyAndFullNumbers() async {
        let ref = UUID()
        let h = Fixtures.makeCoordinator(
            online: false,
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        let payload = h.coordinator.composerFallback()
        #expect(payload != nil)
        #expect(payload?.recipients == ["+16175550123"])      // full number, composer only
        #expect(payload?.body.contains("WHOOSH ALERT: Alex") == true)
        #expect(payload?.body.contains("not an emergency service") == true)
    }

    @Test func composerPayloadHasDelayWordingWhenDelayed() async {
        let ref = UUID()
        let h = Fixtures.makeCoordinator(
            online: false,
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        // Let time pass so the delay clause appears (>= 60 s).
        h.clock.advance(by: 120)
        let payload = h.coordinator.composerFallback()
        #expect(payload?.body.contains("Message delayed by") == true)
    }

    @Test func composerPayloadNilWithNoReachableContact() {
        let h = Fixtures.makeCoordinator(
            contacts: [EmergencyContact(id: UUID(), label: "Dad", e164: "+16175550199", verification: .unverified)]
        )
        // Disarmed (no reachable) ⇒ no event, and no composer payload.
        #expect(h.coordinator.composerFallback() == nil)
    }

    // MARK: - Drill hides Call 911 on the status screen

    @Test func drillStatusHidesCallButton() async {
        let ref = UUID()
        let h = Fixtures.makeCoordinator(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 3, updatedAt: Self.t0)],
            deduplicated: false
        )
        h.detector.emitDrill()
        h.coordinator.sendNow()
        await Fixtures.drain()
        #expect(h.coordinator.isDrill)   // view renders the inert Demo tag
    }
}
