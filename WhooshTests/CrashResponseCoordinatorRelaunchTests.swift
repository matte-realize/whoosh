import Foundation
import Testing
@testable import Whoosh

/// Persistence and relaunch-recovery tests for `CrashResponseCoordinator`
/// (crash-response task 14): REL-1…4. A "relaunch" rebuilds a fresh coordinator
/// over the **same** in-memory repository / stores, then calls
/// `reconcileOnLaunch()` so the reducer's `relaunch` rows run (Requirement
/// 13.4–13.6).
@MainActor
struct CrashResponseCoordinatorRelaunchTests {
    static let t0 = CrashResponseCoordinatorTests.t0
    private var t0: Date { Self.t0 }

    /// Shared backing stores so a relaunched coordinator sees the same data.
    struct World {
        let repo: InMemoryCrashAlertRepository
        let contactStore: InMemoryEmergencyContactStore
        let consentStore: InMemoryConsentStore
        let settingsStore: InMemoryCrashAlertSettingsStore
    }

    static func makeWorld(reachable: EmergencyContact) -> World {
        let repo = InMemoryCrashAlertRepository()
        let contactStore = InMemoryEmergencyContactStore()
        try? contactStore.add(reachable)
        let consentStore = InMemoryConsentStore()
        consentStore.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: t0)
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        return World(repo: repo, contactStore: contactStore, consentStore: consentStore, settingsStore: settingsStore)
    }

    static func makeCoordinator(
        world: World,
        clock: TestClock,
        notifier: FakeCrashNotifier,
        connectivity: FakeConnectivityMonitor
    ) -> CrashResponseCoordinator {
        connectivity.start()
        return CrashResponseCoordinator(
            detector: FakeCrashDetector(),
            rideContext: FakeRideContext(isRideActive: true, isRecordingOrSignalLost: true, currentRideID: UUID()),
            footageBuffer: FakeFootageBuffer(),
            notifier: notifier,
            scheduler: FakeCrashNotificationScheduler(),
            feedback: FakeCountdownFeedback(),
            connectivity: connectivity,
            contactStore: world.contactStore,
            consentStore: world.consentStore,
            settingsStore: world.settingsStore,
            repository: world.repo,
            clock: clock
        )
    }

    /// Persist a record directly in a given state for a relaunch scenario.
    static func seedRecord(
        in world: World,
        state: CrashEventState,
        detectedAt: Date,
        deadline: Date?,
        totalSeconds: TimeInterval? = 30,
        attempts: [AlertAttempt] = []
    ) -> UUID {
        let id = UUID()
        let event = CrashEvent(
            id: id,
            detectedAt: detectedAt,
            utcOffsetMinutes: -240,
            isDrill: false,
            source: "simulator",
            confidence: 1,
            rideId: UUID(),
            state: state,
            countdown: deadline.map { CountdownState(deadline: $0, totalSeconds: totalSeconds ?? 30) },
            suppressedUntil: nil,
            locationAtDetection: .unavailable,
            footageRef: nil,
            outcome: nil
        )
        let record = CrashAlertRecord(
            event: event, locationAtSend: nil, templateVersion: 1,
            renderedText: "", attempts: attempts, createdAt: detectedAt, updatedAt: detectedAt
        )
        try? world.repo.save(record)
        return id
    }

    static let reachable = EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable)

    // MARK: - REL-1: countdown with time left resumes

    @Test func rel1_countdownWithTimeLeftResumes() {
        let world = Self.makeWorld(reachable: Self.reachable)
        // Deadline 20 s in the future relative to the relaunch time.
        let relaunchNow = t0.addingTimeInterval(10)
        _ = Self.seedRecord(in: world, state: .countdown, detectedAt: t0, deadline: t0.addingTimeInterval(30))
        let clock = TestClock(now: relaunchNow)
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: FakeCrashNotifier(), connectivity: FakeConnectivityMonitor(isOnline: true))
        coord.reconcileOnLaunch()
        #expect(coord.eventState == .countdown)
        #expect(coord.isTakeoverPresented)
        #expect(coord.remainingSeconds == 20)
    }

    // MARK: - REL-2: deadline passed ⇒ recoveryPrompted (no auto-send)

    @Test func rel2_deadlinePassedPromptsRecovery() async {
        let world = Self.makeWorld(reachable: Self.reachable)
        _ = Self.seedRecord(in: world, state: .countdown, detectedAt: t0, deadline: t0.addingTimeInterval(30))
        let clock = TestClock(now: t0.addingTimeInterval(60))  // past the deadline
        let notifier = FakeCrashNotifier()
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: notifier, connectivity: FakeConnectivityMonitor(isOnline: true))
        coord.reconcileOnLaunch()
        #expect(coord.eventState == .recoveryPrompted)
        #expect(coord.isRecoveryPromptPresented)
        await CrashResponseCoordinatorTests.drain()
        #expect(notifier.sendCallCount == 0)  // never auto-sends
    }

    // MARK: - REL-3: sending resumes idempotently with the same crashEventId

    @Test func rel3_sendingResumesSameEventId() async {
        let world = Self.makeWorld(reachable: Self.reachable)
        let id = Self.seedRecord(in: world, state: .sending, detectedAt: t0, deadline: nil)
        let clock = TestClock(now: t0.addingTimeInterval(60))  // within the stale limit
        let notifier = FakeCrashNotifier()
        notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: Self.reachable.id, status: .queued, segments: 4, updatedAt: t0)],
            deduplicated: false
        )
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: notifier, connectivity: FakeConnectivityMonitor(isOnline: true))
        coord.reconcileOnLaunch()
        await CrashResponseCoordinatorTests.drain()
        #expect(notifier.sendCallCount == 1)
        #expect(notifier.sendRequests.first?.crashEventId == id)  // same key
        #expect(coord.eventState == .sent)
    }

    // MARK: - REL-4: resting state untouched

    @Test func rel4_restingStateUntouched() async {
        let world = Self.makeWorld(reachable: Self.reachable)
        _ = Self.seedRecord(in: world, state: .sent, detectedAt: t0, deadline: nil)
        let clock = TestClock(now: t0.addingTimeInterval(60))
        let notifier = FakeCrashNotifier()
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: notifier, connectivity: FakeConnectivityMonitor(isOnline: true))
        // activeEvent() returns nil for a resting (sent) record, so reconcile is
        // a no-op and the coordinator stays idle.
        coord.reconcileOnLaunch()
        #expect(coord.eventState == .idle)
        await CrashResponseCoordinatorTests.drain()
        #expect(notifier.sendCallCount == 0)
    }

    // MARK: - Relaunch of queuedOffline resumes retries; stale past limit

    @Test func relaunch_queuedOfflineWithinStaleResumes() {
        let world = Self.makeWorld(reachable: Self.reachable)
        _ = Self.seedRecord(in: world, state: .queuedOffline, detectedAt: t0, deadline: nil)
        let clock = TestClock(now: t0.addingTimeInterval(120))  // within stale
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: FakeCrashNotifier(), connectivity: FakeConnectivityMonitor(isOnline: false))
        coord.reconcileOnLaunch()
        #expect(coord.eventState == .queuedOffline)
        #expect(coord.bannerKind == .queuedOffline)
    }

    @Test func relaunch_queuedOfflinePastStaleBecomesStale() {
        let world = Self.makeWorld(reachable: Self.reachable)
        _ = Self.seedRecord(in: world, state: .queuedOffline, detectedAt: t0, deadline: nil)
        let clock = TestClock(now: t0.addingTimeInterval(31 * 60))  // past stale
        let coord = Self.makeCoordinator(world: world, clock: clock, notifier: FakeCrashNotifier(), connectivity: FakeConnectivityMonitor(isOnline: false))
        coord.reconcileOnLaunch()
        #expect(coord.eventState == .stale)
    }

    // MARK: - Persistence: record saved on every transition

    @Test func persistence_recordSavedThroughFlow() async {
        let world = Self.makeWorld(reachable: Self.reachable)
        let clock = TestClock(now: t0)
        let detector = FakeCrashDetector()
        let notifier = FakeCrashNotifier()
        notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: Self.reachable.id, status: .queued, segments: 4, updatedAt: t0)],
            deduplicated: false
        )
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        connectivity.start()
        let coord = CrashResponseCoordinator(
            detector: detector,
            rideContext: FakeRideContext(isRideActive: true, isRecordingOrSignalLost: true, currentRideID: UUID()),
            footageBuffer: FakeFootageBuffer(),
            notifier: notifier,
            scheduler: FakeCrashNotificationScheduler(),
            feedback: FakeCountdownFeedback(),
            connectivity: connectivity,
            contactStore: world.contactStore,
            consentStore: world.consentStore,
            settingsStore: world.settingsStore,
            repository: world.repo,
            clock: clock
        )
        detector.start()
        detector.emit()
        // A record exists in detected/countdown.
        #expect((try? world.repo.all())?.isEmpty == false)
        coord.sendNow()
        await CrashResponseCoordinatorTests.drain()
        let record = (try? world.repo.all())?.first
        #expect(record?.event.state == .sent)
        #expect(record?.attempts.isEmpty == false)
    }
}
