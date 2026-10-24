import Foundation
import Testing
@testable import Whoosh

/// Failure / offline-queue / stale / composer-fallback / polling tests for
/// `CrashResponseCoordinator` (crash-response task 13): NET-1…5, BE-1…10,
/// DEL-1…3, F-COMP-1, and the flapping-connectivity-sends-once case. Fakes only.
@MainActor
struct CrashResponseCoordinatorFailureTests {
    typealias Harness = CrashResponseCoordinatorTests.Harness
    static let t0 = CrashResponseCoordinatorTests.t0
    private var t0: Date { Self.t0 }

    private static func make(
        online: Bool = true,
        sendBehavior: FakeCrashNotifier.Behavior? = nil,
        contacts: [EmergencyContact]? = nil
    ) -> Harness {
        CrashResponseCoordinatorTests.makeCoordinator(
            online: online, contacts: contacts, sendBehavior: sendBehavior
        )
    }

    private static func drain() async { await CrashResponseCoordinatorTests.drain() }

    private static func queued(_ ref: UUID) -> FakeCrashNotifier.Behavior {
        .success(recipients: [CrashRecipientResult(recipientRef: ref, status: .queued, segments: 4, updatedAt: t0)],
                 deduplicated: false)
    }

    // MARK: - NET: connectivity

    @Test func net1_offlineAtExpiryQueues() {
        let h = Self.make(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        #expect(h.notifier.sendCallCount == 0)
        #expect(h.coordinator.bannerKind == .queuedOffline)
        #expect(h.coordinator.isComposerFallbackOffered)
    }

    @Test func net2_onlineInsideStaleSendsWithDelay() async {
        let ref = UUID()
        let h = Self.make(
            online: false,
            sendBehavior: Self.queued(ref),
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        // Connectivity returns well within the stale limit.
        h.clock.advance(by: 120)
        h.connectivity.setOnline(true)
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        // Delayed wording: delayedSeconds >= 60 at send time.
        #expect((h.notifier.sendRequests.first?.delayedSeconds ?? 0) >= 60)
    }

    @Test func net3_onlineAfterStaleNeverSends() async {
        let h = Self.make(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        // Past the 30-min stale limit before connectivity returns.
        h.clock.advance(by: 31 * 60)
        h.connectivity.setOnline(true)
        await Self.drain()
        #expect(h.coordinator.eventState == .stale)
        #expect(h.notifier.sendCallCount == 0)
        #expect(h.coordinator.bannerKind == .stale)
    }

    @Test func net4_flappingConnectivitySendsOnce() async {
        let ref = UUID()
        let h = Self.make(
            online: false,
            sendBehavior: Self.queued(ref),
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        // Flap: offline→online fires one retry; subsequent flaps while sent must
        // not produce more sends.
        h.connectivity.setOnline(true)
        await Self.drain()
        h.connectivity.setOnline(false)
        h.connectivity.setOnline(true)
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        #expect(h.notifier.sendCallCount == 1)
    }

    @Test func net5_offlineThenCancelNoSend() {
        let h = Self.make(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
    }

    // MARK: - BE: backend failures

    @Test func be_retryableThenSuccessViaBackoff() async {
        let ref = UUID()
        let h = Self.make(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.notifier.sendBehaviors = [
            .failure(CrashNotifierError(.serverError)),
            Self.queued(ref),
        ]
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        // First attempt failed ⇒ retry scheduled; still sending.
        #expect(h.coordinator.eventState == .sending)
        // Advance past the first backoff (5 s) to fire the retry.
        h.clock.advance(by: 5)
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        #expect(h.notifier.sendCallCount == 2)
    }

    @Test func be_nonRetryableImmediateFallback() async {
        let h = Self.make()
        h.notifier.sendBehavior = .failure(CrashNotifierError(.serviceDisabled))
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .fallbackPrompted)
        #expect(h.coordinator.isComposerFallbackOffered)
        #expect(h.scheduler.notSentNotices.isEmpty == false)
    }

    @Test func be_rateLimitedNonRetryable() async {
        let h = Self.make()
        h.notifier.sendBehavior = .failure(CrashNotifierError(.rateLimited))
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .fallbackPrompted)
    }

    @Test func be_timeoutRetriesOnceThenFails() async {
        let h = Self.make()
        h.notifier.sendBehavior = .timeout
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        // First timeout ⇒ single retry scheduled.
        #expect(h.coordinator.eventState == .sending)
        #expect(h.coordinator.machine.timeoutRetryUsed)
        h.clock.advance(by: 5)
        await Self.drain()
        // Second timeout ⇒ fail → fallback.
        #expect(h.coordinator.eventState == .fallbackPrompted)
    }

    @Test func be_partialPerRecipientFailureCountsAsSent() async {
        let a = UUID(); let b = UUID()
        let h = Self.make(
            contacts: [
                EmergencyContact(id: a, label: "Mom", e164: "+16175550123", verification: .reachable),
                EmergencyContact(id: b, label: "Dad", e164: "+16175550124", verification: .reachable),
            ]
        )
        h.notifier.sendBehavior = .success(
            recipients: [
                CrashRecipientResult(recipientRef: a, status: .queued, segments: 4, updatedAt: t0),
                CrashRecipientResult(recipientRef: b, status: .rejected, whooshErrorCode: "recipient_invalid", providerErrorCode: 21211, segments: 0, updatedAt: t0),
            ],
            deduplicated: false
        )
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        // At least one recipient queued ⇒ event is sent.
        #expect(h.coordinator.eventState == .sent)
    }

    @Test func be_unauthenticatedIsRetryable() async {
        let h = Self.make()
        h.notifier.sendBehavior = .failure(CrashNotifierError(.unauthenticated))
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sending)  // retry scheduled
    }

    // MARK: - DEL: delivery status after sent (polling)

    @Test func del1_undeliveredAfterSentUpdatesContact() async {
        let ref = UUID()
        let eventId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let h = Self.make(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        // Initial send: queued.
        h.notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 4, updatedAt: t0)],
            deduplicated: false
        )
        // Poll result: undelivered.
        h.notifier.statusResults[eventId] = CrashNotificationResult(
            crashEventId: eventId, kind: .crashAlert, deduplicated: false,
            recipients: [CrashRecipientResult(recipientRef: ref, status: .undelivered, whooshErrorCode: "recipient_unreachable", providerErrorCode: 30003, segments: 4, updatedAt: t0.addingTimeInterval(5))]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        // Immediate poll runs on startStatusPolling; drain it.
        await Self.drain()
        let contact = (try? h.contactStore.contacts())?.first { $0.id == ref }
        #expect(contact?.verification == .undeliverable)
    }

    @Test func del2_statusMonotonicDeliveredNotOverwritten() async {
        let ref = UUID()
        let eventId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let h = Self.make(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .delivered, segments: 4, updatedAt: t0.addingTimeInterval(10))],
            deduplicated: false
        )
        // A later (stale) queued status must not regress a delivered attempt.
        h.notifier.statusResults[eventId] = CrashNotificationResult(
            crashEventId: eventId, kind: .crashAlert, deduplicated: false,
            recipients: [CrashRecipientResult(recipientRef: ref, status: .queued, segments: 4, updatedAt: t0)]
        )
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        await Self.drain()
        let display = h.coordinator.recipients.first { $0.recipientRef == ref }
        #expect(display?.status == .delivered)
    }

    @Test func del3_optedOutStatusMarksContact() async {
        let ref = UUID()
        let h = Self.make(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .failed, whooshErrorCode: "recipient_opted_out", providerErrorCode: 21610, segments: 0, updatedAt: t0)],
            deduplicated: false
        )
        // Any-progress is false (only failed) ⇒ non-retryable fallback, but the
        // attempt still records opted-out and updates the contact.
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        let contact = (try? h.contactStore.contacts())?.first { $0.id == ref }
        #expect(contact?.verification == .optedOut)
    }

    // MARK: - F-COMP: composer fallback flag

    @Test func fcomp1_composerOfferedWhenQueuedOrFailed() async {
        let h = Self.make(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.isComposerFallbackOffered)  // queuedOffline
    }

    // MARK: - Consent revoked while queued

    @Test func consentRevokedWhileQueuedCancels() {
        let h = Self.make(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        h.coordinator.consentRevoked()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
    }
}
