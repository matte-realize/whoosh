import Foundation
import Testing
@testable import Whoosh

/// End-to-end integration tests for the crash-response feature (crash-response
/// task 27). Unlike `CrashResponseCoordinatorTests` (which uses `FakeRideContext`),
/// these wire the **real** stack the composition root builds:
///
/// - a real `RideSessionViewModel` over `FakeLocationTracker` + `TestClock`,
/// - a real `RideSessionBridge` publishing the `RideContext` and arming the
///   detector as the ride records,
/// - a real `CrashResponseCoordinator` + the real pure reducer,
/// - the real `DebugCrashSimulator` detector and, for the Tier 0 composer
///   fallback, the real `NoopCrashNotifier` (which throws `serviceDisabled`).
///
/// Scenarios: a full ride → simulated detector signal → countdown → expire →
/// Tier 0 composer-fallback state → record in the log; the cancel path; and the
/// drill path. Everything runs offline, with no network.
@MainActor
struct CrashIntegrationTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    struct Harness {
        let ride: RideSessionViewModel
        let bridge: RideSessionBridge
        let coordinator: CrashResponseCoordinator
        let simulator: DebugCrashSimulator
        let repo: InMemoryCrashAlertRepository
        let scheduler: FakeCrashNotificationScheduler
        let clock: TestClock
        let tracker: FakeLocationTracker
    }

    /// Build the real stack. `notifier` defaults to the Tier 0 `NoopCrashNotifier`
    /// so an expiry lands in the composer-fallback state; pass a fake to script
    /// a success instead.
    static func makeHarness(
        notifier: CrashNotifier = NoopCrashNotifier(),
        online: Bool = true,
        reachableContacts: Int = 1,
        riderLabel: String? = "Alex",
        enabled: Bool = true,
        consentVersion: Int? = 1
    ) -> Harness {
        let clock = TestClock(now: t0)
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        let ride = RideSessionViewModel(
            tracker: tracker,
            clock: clock,
            repository: InMemoryRideRepository(),
            tuning: RideTuning()
        )

        let contactStore = InMemoryEmergencyContactStore()
        for i in 0..<reachableContacts {
            try? contactStore.add(
                EmergencyContact(
                    id: UUID(),
                    label: "Contact\(i)",
                    e164: "+161755501\(String(format: "%02d", i))",
                    verification: .reachable
                )
            )
        }
        let consentStore = InMemoryConsentStore()
        if let v = consentVersion {
            consentStore.record(version: v, acknowledgedNotGuaranteed: true, acceptedAt: t0)
        }
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: enabled, riderLabel: riderLabel, developerToolsEnabled: true)
        )
        let repo = InMemoryCrashAlertRepository()
        let scheduler = FakeCrashNotificationScheduler()
        let connectivity = FakeConnectivityMonitor(isOnline: online)
        connectivity.start()
        let simulator = DebugCrashSimulator(clock: clock)

        // Build the relay first so the coordinator holds a stable RideContext;
        // its `underlying` is set to the real bridge once the bridge exists.
        let relay = RelayToBridge()
        let coordinator = CrashResponseCoordinator(
            detector: simulator,
            rideContext: relay,
            footageBuffer: FakeFootageBuffer(),
            notifier: notifier,
            scheduler: scheduler,
            feedback: FakeCountdownFeedback(),
            connectivity: connectivity,
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: repo,
            clock: clock
        )

        let bridge = RideSessionBridge(
            rideViewModel: ride,
            detector: simulator,
            armingInputs: {
                let s = settingsStore.current()
                let reachable = contactStore.contactsOrEmpty().filter { $0.verification == .reachable }.count
                return RideSessionBridge.ArmingInputs(
                    enabled: s.enabled,
                    consentCurrent: consentStore.current()?.isCurrent(minimumVersion: 1) ?? false,
                    riderLabelPresent: (s.riderLabel?.isEmpty == false),
                    reachableContactCount: reachable
                )
            }
        )
        // Point the coordinator's relay at the real bridge.
        relay.underlying = bridge

        return Harness(
            ride: ride, bridge: bridge, coordinator: coordinator, simulator: simulator,
            repo: repo, scheduler: scheduler, clock: clock, tracker: tracker
        )
    }

    static func drain() async {
        for _ in 0..<8 { await Task.yield() }
    }

    /// Start a ride and arm detection (recording + armed inputs).
    static func startRecording(_ h: Harness) {
        h.ride.start()
        h.bridge.start()
        #expect(h.ride.rideState == .recording)
        #expect(h.simulator.isMonitoring)
    }

    // MARK: - Full ride → signal → countdown → expire → Tier 0 fallback → record

    @Test func fullRideExpireTier0ComposerFallbackAndRecord() async {
        let h = Self.makeHarness()  // Noop notifier (Tier 0)
        Self.startRecording(h)

        // Simulate a (non-drill) crash through the real detector.
        h.simulator.simulateCrash(isDrill: false)
        #expect(h.coordinator.eventState == .countdown)
        #expect(h.coordinator.isTakeoverPresented)

        // Let the countdown expire; the Noop notifier throws serviceDisabled
        // (non-retryable) so the event fails into the composer-fallback state.
        h.clock.advance(by: 30)
        await Self.drain()

        #expect(h.coordinator.eventState == .fallbackPrompted)
        #expect(h.coordinator.isComposerFallbackOffered)
        #expect(h.coordinator.bannerKind == .failed)

        // The composer fallback is pre-filled by the shared builder.
        let payload = h.coordinator.composerFallback()
        #expect(payload != nil)
        #expect(payload?.recipients.count == 1)
        #expect(payload?.body.contains("WHOOSH ALERT") == true)

        // The attempt was recorded in the log (crash_alert, not a drill).
        let record = (try? h.repo.all())?.first
        #expect(record != nil)
        #expect(record?.event.isDrill == false)
        #expect(record?.event.state == .fallbackPrompted)
    }

    // MARK: - Cancel path (nothing sent, suppression starts)

    @Test func fullRideCancelPathSendsNothing() async {
        let h = Self.makeHarness()
        Self.startRecording(h)

        h.simulator.simulateCrash(isDrill: false)
        #expect(h.coordinator.eventState == .countdown)

        // Rider taps "I'm OK — Cancel" mid-countdown.
        h.clock.advance(by: 10)
        h.coordinator.riderCancel()
        await Self.drain()

        #expect(h.coordinator.eventState == .cancelled)
        #expect(h.coordinator.isTakeoverPresented == false)
        // A cancelled record exists; nothing was sent.
        let record = (try? h.repo.all())?.first
        #expect(record?.event.outcome == .riderCancelled)
        // The backup notification was cancelled.
        #expect(h.scheduler.cancellations.isEmpty == false)
    }

    // MARK: - Drill path (demo) → success via fake notifier, labelled drill

    @Test func fullRideDrillPathSendsDrillAndRecords() async {
        // A scriptable notifier that accepts the drill send (demo success).
        let notifier = FakeCrashNotifier()
        let h = Self.makeHarness(notifier: notifier)
        // Script a success for whatever recipient the coordinator sends to.
        notifier.sendBehavior = .success(recipients: [], deduplicated: false)
        // Use a result that reports progress so the event reaches `sent`.
        Self.startRecording(h)

        // A drill through the simulator (the "Simulate crash" demo path).
        h.simulator.simulateCrash(isDrill: true)
        #expect(h.coordinator.isDrill)
        #expect(h.coordinator.eventState == .countdown)

        // Re-script: queue a success with the actual reachable recipient.
        let reachable = h.coordinator.recipients.first
        #expect(reachable != nil)
        if let ref = reachable?.recipientRef {
            notifier.sendBehavior = .success(
                recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 3, updatedAt: Self.t0)],
                deduplicated: false
            )
        }

        h.coordinator.sendNow()
        await Self.drain()

        #expect(h.coordinator.eventState == .sent)
        #expect(notifier.sendRequests.first?.kind == .drill)
        // A drill does not consume the real-alert per-ride cap.
        #expect(h.coordinator.machine.perRideSentCount == 0)

        // The record is labelled a drill.
        let record = (try? h.repo.all())?.first
        #expect(record?.event.isDrill == true)
    }

    // MARK: - Pausing the ride disarms detection (no signal possible)

    @Test func pausingRideDisarmsDetector() {
        let h = Self.makeHarness()
        Self.startRecording(h)
        h.ride.pause()
        h.bridge.reevaluateArming()
        #expect(h.simulator.isMonitoring == false)
        // A simulated crash while disarmed does nothing.
        h.simulator.simulateCrash(isDrill: false)
        #expect(h.coordinator.eventState == .idle)
    }
}

/// A test-only relay `RideContext` forwarding to a late-bound `underlying`
/// (the real bridge), mirroring the composition root's `RelayRideContext` so
/// the single coordinator can track a ride created after it.
@MainActor
private final class RelayToBridge: RideContext {
    var underlying: RideContext?
    var isRideActive: Bool { underlying?.isRideActive ?? false }
    var isRecordingOrSignalLost: Bool { underlying?.isRecordingOrSignalLost ?? false }
    var latestAcceptedFix: RideFix? { underlying?.latestAcceptedFix }
    var currentRideID: UUID? { underlying?.currentRideID }
}
