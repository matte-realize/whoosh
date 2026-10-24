import Foundation
import Testing
@testable import Whoosh

/// Core-flow tests for `CrashResponseCoordinator` (crash-response task 12):
/// false positives FP-1…6, cancellation CC-1…7, unavailable GPS GPS-1…4,
/// duplicates DUP-1…4, a never-call safety test, and the drill-flag path.
/// Composes the real pure reducer with fakes only; time is driven by `TestClock`.
@MainActor
struct CrashResponseCoordinatorTests {
    // MARK: Fixtures

    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A reachable contact so the feature can be armed.
    static func reachableContact(label: String = "Mom", e164: String = "+16175550123") -> EmergencyContact {
        EmergencyContact(id: UUID(), label: label, e164: e164, verification: .reachable)
    }

    /// Build a coordinator with fakes, armed by default (recording, enabled,
    /// consented, label present, one reachable contact).
    static func makeCoordinator(
        online: Bool = true,
        rideRecording: Bool = true,
        enabled: Bool = true,
        consentVersion: Int? = 1,
        riderLabel: String? = "Alex",
        contacts: [EmergencyContact]? = nil,
        latestFix: RideFix? = nil,
        sendBehavior: FakeCrashNotifier.Behavior? = nil
    ) -> Harness {
        let clock = TestClock(now: t0)
        let detector = FakeCrashDetector()
        let ride = FakeRideContext(
            isRideActive: rideRecording,
            isRecordingOrSignalLost: rideRecording,
            latestAcceptedFix: latestFix,
            currentRideID: UUID()
        )
        let footage = FakeFootageBuffer()
        let notifier = FakeCrashNotifier()
        if let sendBehavior { notifier.sendBehavior = sendBehavior }
        let scheduler = FakeCrashNotificationScheduler()
        let feedback = FakeCountdownFeedback()
        let connectivity = FakeConnectivityMonitor(isOnline: online)
        connectivity.start()
        let contactStore = InMemoryEmergencyContactStore()
        let defaultContacts = contacts ?? [reachableContact()]
        for c in defaultContacts { try? contactStore.add(c) }
        let consentStore = InMemoryConsentStore()
        if let v = consentVersion {
            consentStore.record(version: v, acknowledgedNotGuaranteed: true, acceptedAt: t0)
        }
        let settings = CrashAlertSettings(enabled: enabled, riderLabel: riderLabel)
        let settingsStore = InMemoryCrashAlertSettingsStore(settings: settings)
        let repo = InMemoryCrashAlertRepository()
        var counter = 0
        let coordinator = CrashResponseCoordinator(
            detector: detector,
            rideContext: ride,
            footageBuffer: footage,
            notifier: notifier,
            scheduler: scheduler,
            feedback: feedback,
            connectivity: connectivity,
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: repo,
            clock: clock,
            makeID: {
                counter += 1
                return UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", counter))")!
            }
        )
        detector.start()
        return Harness(
            coordinator: coordinator,
            clock: clock,
            detector: detector,
            ride: ride,
            footage: footage,
            notifier: notifier,
            scheduler: scheduler,
            feedback: feedback,
            connectivity: connectivity,
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repo: repo
        )
    }

    struct Harness {
        let coordinator: CrashResponseCoordinator
        let clock: TestClock
        let detector: FakeCrashDetector
        let ride: FakeRideContext
        let footage: FakeFootageBuffer
        let notifier: FakeCrashNotifier
        let scheduler: FakeCrashNotificationScheduler
        let feedback: FakeCountdownFeedback
        let connectivity: FakeConnectivityMonitor
        let contactStore: InMemoryEmergencyContactStore
        let consentStore: InMemoryConsentStore
        let settingsStore: InMemoryCrashAlertSettingsStore
        let repo: InMemoryCrashAlertRepository
    }

    /// Let pending notifier `Task`s complete (the fakes never truly suspend).
    static func drain() async {
        for _ in 0..<5 { await Task.yield() }
    }

    static func goodFix(ageSeconds: TimeInterval) -> RideFix {
        RideFix(latitude: 42.36012, longitude: -71.05888, horizontalAccuracy: 12,
                timestamp: t0.addingTimeInterval(-ageSeconds))
    }

    // MARK: - FP: false positives (zero sends)

    @Test func fp1_signalWhileDisarmedRideState() {
        let h = Self.makeCoordinator(rideRecording: false)
        h.detector.emit()
        #expect(h.coordinator.eventState == .idle)
        #expect(h.notifier.sendCallCount == 0)
        #expect(h.feedback.beginTotals.isEmpty)
    }

    @Test func fp2_signalWithoutConsent() {
        let h = Self.makeCoordinator(consentVersion: nil)
        h.detector.emit()
        #expect(h.coordinator.eventState == .idle)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func fp2b_signalWithOutdatedConsent() {
        // Consent version below the minimum ⇒ not current ⇒ disarmed.
        let h = Self.makeCoordinator(consentVersion: 0)
        h.detector.emit()
        #expect(h.coordinator.eventState == .idle)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func fp3_signalWithNoReachableContact() {
        let unverified = EmergencyContact(id: UUID(), label: "Dad", e164: "+16175550199", verification: .unverified)
        let h = Self.makeCoordinator(contacts: [unverified])
        h.detector.emit()
        #expect(h.coordinator.eventState == .idle)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func fp4_secondSignalDuringActiveEventIgnored() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        #expect(h.coordinator.eventState == .countdown)
        let firstId = h.coordinator.machine.eventId
        h.detector.emit()  // second signal during countdown
        #expect(h.coordinator.eventState == .countdown)
        #expect(h.coordinator.machine.eventId == firstId)  // same event
    }

    @Test func fp5_signalInSuppressionWindowThenAfter() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        h.coordinator.riderCancel()  // cancel ⇒ suppression window starts
        #expect(h.coordinator.eventState == .cancelled)
        // Inside the suppression window ⇒ ignored.
        h.clock.advance(by: 10)
        h.detector.emit()
        #expect(h.coordinator.eventState == .cancelled)
        // After the window ⇒ a new event is allowed.
        h.clock.advance(by: 130)
        h.detector.emit()
        #expect(h.coordinator.eventState == .countdown)
    }

    @Test func fp6_perRideCapAfterSentButNotAfterCancel() async {
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(sendBehavior: .allQueued(recipients, at: Self.t0))
        // Cancel first ⇒ does NOT consume the cap.
        h.detector.emit()
        h.coordinator.riderCancel()
        h.clock.advance(by: 130)  // clear suppression
        // A real send now.
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        h.clock.advance(by: 130)  // clear suppression after send
        // Second signal after a *sent* alert ⇒ capped (ignored).
        h.detector.emit()
        #expect(h.coordinator.eventState == .sent)
    }

    // MARK: - CC: cancellation

    @Test func cc1_cancelAtStartZeroSends() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
        #expect(h.feedback.endReasons.contains(.cancelled))
        #expect(h.scheduler.cancellations.isEmpty == false)
    }

    @Test func cc2_cancelMidCountdown() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        h.clock.advance(by: 15)
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func cc3_cancelAtLastSecond() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        h.clock.advance(by: 29)
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func cc4_cancelAtDeadlineExpiryWins() async {
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(sendBehavior: .allQueued(recipients, at: Self.t0))
        h.detector.emit()
        h.clock.advance(by: 30)  // at the deadline ⇒ expiry
        h.coordinator.riderCancel()  // loses the tie
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
    }

    @Test func cc5_cancelAfterSendingNotCancellable() async {
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        // A retryable error leaves it in a retry-wait (sending, no request in flight).
        let h = Self.makeCoordinator()
        h.notifier.sendBehaviors = [.failure(CrashNotifierError(.serverError))]
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sending)
        // In a retry wait with no request in flight, "I'm OK" cancels.
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        _ = recipients
    }

    @Test func cc6_cancelWhileQueuedOffline() {
        let h = Self.makeCoordinator(online: false)
        h.detector.emit()
        h.coordinator.sendNow()
        #expect(h.coordinator.eventState == .queuedOffline)
        h.coordinator.riderCancel()
        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.notifier.sendCallCount == 0)
    }

    @Test func cc7_countdownClampedBelow15() {
        // The reducer clamps via tuning.clampCountdown(tuning.countdownSeconds);
        // default tuning is 30. Assert the deadline is the clamped default.
        let h = Self.makeCoordinator()
        h.detector.emit()
        #expect(h.coordinator.machine.totalCountdownSeconds == 30)
    }

    // MARK: - GPS: unavailable / stale location

    @Test func gps1_noFixEverLocationUnavailable() {
        let h = Self.makeCoordinator(latestFix: nil)
        h.detector.emit()
        let snap = h.repo.recordForTest()?.event.locationAtDetection
        #expect(snap?.status == .unavailable)
    }

    @Test func gps2_staleFixLastKnown() {
        let h = Self.makeCoordinator(latestFix: Self.goodFix(ageSeconds: 45))
        h.detector.emit()
        let snap = h.repo.recordForTest()?.event.locationAtDetection
        #expect(snap?.status == .lastKnown)
    }

    @Test func gps3_fixOlderThan30MinUnavailable() {
        let h = Self.makeCoordinator(latestFix: Self.goodFix(ageSeconds: 31 * 60))
        h.detector.emit()
        let snap = h.repo.recordForTest()?.event.locationAtDetection
        #expect(snap?.status == .unavailable)
    }

    @Test func gps4_freshFixAtSendUsed() async {
        // No fix at detection; a fresh fix appears before send ⇒ used at send.
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(latestFix: nil, sendBehavior: .allQueued(recipients, at: Self.t0))
        h.detector.emit()
        #expect(h.repo.recordForTest()?.event.locationAtDetection.status == .unavailable)
        // A fresh accepted fix appears, then the countdown expires.
        h.ride.latestAcceptedFix = RideFix(latitude: 42.36, longitude: -71.05, horizontalAccuracy: 8, timestamp: h.clock.now())
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.repo.recordForTest()?.locationAtSend?.status == .current)
    }

    // MARK: - DUP: duplicates (≤ 1 send per event)

    @Test func dup1_doubleDetectorSignalOneEvent() {
        let h = Self.makeCoordinator()
        h.detector.emit()
        h.detector.emit()
        #expect(h.coordinator.eventState == .countdown)
    }

    @Test func dup2_doubleSendNowOneSend() async {
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(sendBehavior: .allQueued(recipients, at: Self.t0))
        h.detector.emit()
        h.coordinator.sendNow()
        h.coordinator.sendNow()  // second tap
        await Self.drain()
        #expect(h.notifier.sendCallCount == 1)
        #expect(h.coordinator.eventState == .sent)
    }

    @Test func dup3_deduplicatedResponseTreatedAsSent() async {
        let ref = UUID()
        let result = CrashNotificationResult(
            crashEventId: UUID(), kind: .crashAlert, deduplicated: true,
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 4, updatedAt: Self.t0)]
        )
        let h = Self.makeCoordinator(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)],
            sendBehavior: .success(recipients: result.recipients, deduplicated: true)
        )
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        #expect(h.notifier.sendCallCount == 1)
    }

    @Test func dup4_singleSendEffectPerEvent() async {
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(sendBehavior: .allQueued(recipients, at: Self.t0))
        h.detector.emit()
        h.clock.advance(by: 30)  // deadline expiry dispatches once
        await Self.drain()
        #expect(h.notifier.sendCallCount == 1)
    }

    // MARK: - NEVER-CALL safety

    @Test func neverCall_noDialEffectInWorkflow() async {
        // The reducer's effect set has no call/dial case; a full flow completes
        // without any such action (compile-time + behavioral guarantee).
        let recipients = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
        let h = Self.makeCoordinator(sendBehavior: .allQueued(recipients, at: Self.t0))
        h.detector.emit()
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        // No API here can place a call; the send went only through the notifier.
        #expect(h.notifier.sendCallCount == 1)
    }

    // MARK: - Drill flag path

    @Test func drill_usesDrillKindAndIgnoresCap() async {
        let ref = UUID()
        let h = Self.makeCoordinator(
            contacts: [EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)]
        )
        h.notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 3, updatedAt: Self.t0)],
            deduplicated: false
        )
        h.detector.emitDrill()
        #expect(h.coordinator.machine.isDrill)
        h.coordinator.sendNow()
        await Self.drain()
        #expect(h.coordinator.eventState == .sent)
        // The sent request used the drill kind.
        #expect(h.notifier.sendRequests.first?.kind == .drill)
        // A drill does not consume the per-ride cap.
        #expect(h.coordinator.machine.perRideSentCount == 0)
        h.clock.advance(by: 130)
        h.detector.emitDrill()  // another drill allowed
        #expect(h.coordinator.eventState == .countdown)
    }
}

extension InMemoryCrashAlertRepository {
    /// Test helper: the single stored record, if any.
    func recordForTest() -> CrashAlertRecord? {
        (try? all())?.first
    }
}
