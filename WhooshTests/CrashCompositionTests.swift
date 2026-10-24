import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Composition-root tests for the crash-response wiring (crash-response task 26).
///
/// Focus: **PRIV-1** — with crash alerts OFF the app behaves exactly like the
/// MVP: no network (the Noop notifier is never called), no sign-in, and no
/// notification authorization prompt. Also verifies the shared `ModelContainer`
/// holds both `RideRecord` and `CrashAlertRecordEntity` without disturbing ride
/// data, and that enabling the feature with a reachable contact arms detection.
///
/// These exercise `CrashResponseEnvironment` directly with fakes (the same shape
/// the composition root builds), so no Core Location, Keychain, or real
/// notification center is touched.
@MainActor
struct CrashCompositionTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Build a `CrashResponseEnvironment` with recording fakes. `enabled`
    /// toggles the feature; `withReachableContact`/`withConsent`/`riderLabel`
    /// supply the other arming inputs.
    static func makeEnv(
        enabled: Bool,
        withReachableContact: Bool = false,
        withConsent: Bool = true,
        riderLabel: String? = "Alex",
        developerTools: Bool = false
    ) -> Fixture {
        let clock = TestClock(now: t0)
        let notifier = FakeCrashNotifier()
        let scheduler = FakeCrashNotificationScheduler()
        let connectivity = FakeConnectivityMonitor(isOnline: true)
        let contactStore = InMemoryEmergencyContactStore()
        if withReachableContact {
            try? contactStore.add(
                EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable)
            )
        }
        let consentStore = InMemoryConsentStore()
        if withConsent {
            consentStore.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: t0)
        }
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: enabled, riderLabel: riderLabel, developerToolsEnabled: developerTools)
        )
        let simulator = developerTools ? DebugCrashSimulator(clock: clock) : nil
        let detector: CrashDetector = simulator ?? NoopCrashDetector()
        let env = CrashResponseEnvironment(
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: InMemoryCrashAlertRepository(),
            connectivity: connectivity,
            scheduler: scheduler,
            notifier: notifier,
            feedback: FakeCountdownFeedback(),
            footageBuffer: FakeFootageBuffer(),
            detector: detector,
            simulator: simulator,
            clock: clock
        )
        return Fixture(env: env, clock: clock, notifier: notifier, scheduler: scheduler, simulator: simulator)
    }

    struct Fixture {
        let env: CrashResponseEnvironment
        let clock: TestClock
        let notifier: FakeCrashNotifier
        let scheduler: FakeCrashNotificationScheduler
        let simulator: DebugCrashSimulator?
    }

    static func drain() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - PRIV-1: crash alerts OFF behaves like the MVP

    @Test func priv1_featureOffReportsOffAndNoMessaging() {
        let f = Self.makeEnv(enabled: false)
        #expect(f.env.isFeatureOn == false)
        // Tier 0 is never "connected" to a messaging backend (no network path).
        #expect(f.env.isMessagingConnected == false)
        // No notifier calls and no authorization prompt at rest.
        #expect(f.notifier.sendCallCount == 0)
        #expect(f.scheduler.authorizationRequestCount == 0)
    }

    @Test func priv1_signalWhileOffNeverSendsOrSchedules() async {
        // Developer tools on so a simulator exists, but the feature itself is OFF
        // ⇒ a simulated crash must do nothing (no countdown, no send, no prompt).
        let f = Self.makeEnv(enabled: false, withReachableContact: true, developerTools: true)
        let session = Self.recordingRideSession(clock: f.clock)
        f.env.attachRide(session)
        session.startForTest()
        f.simulator?.simulateCrash()
        await Self.drain()
        #expect(f.env.coordinator.eventState == .idle)
        #expect(f.notifier.sendCallCount == 0)
        #expect(f.scheduler.deadlinePrompts.isEmpty)
        #expect(f.scheduler.authorizationRequestCount == 0)
    }

    @Test func reconcileOnLaunchWithNoEventIsSafe() {
        let f = Self.makeEnv(enabled: false)
        f.env.reconcileOnLaunch() // no active event persisted
        #expect(f.env.coordinator.eventState == .idle)
    }

    // MARK: - Feature ON arms detection and runs the flow

    @Test func featureOnArmsDetectorWhileRecording() {
        let f = Self.makeEnv(enabled: true, withReachableContact: true, developerTools: true)
        let session = Self.recordingRideSession(clock: f.clock)
        f.env.attachRide(session)
        session.startForTest()
        // Arming is a function of ride state + feature/consent/label/contacts.
        f.env.reevaluateArming()
        #expect(f.simulator?.isMonitoring == true)
        // Detaching the ride disarms.
        f.env.detachRide()
        #expect(f.simulator?.isMonitoring == false)
    }

    @Test func featureOnSimulatedCrashStartsCountdown() async {
        let f = Self.makeEnv(enabled: true, withReachableContact: true, developerTools: true)
        let session = Self.recordingRideSession(clock: f.clock)
        f.env.attachRide(session)
        session.startForTest()
        f.env.reevaluateArming()
        f.simulator?.simulateCrash()
        await Self.drain()
        #expect(f.env.coordinator.eventState == .countdown)
        #expect(f.env.coordinator.isTakeoverPresented)
    }

    // MARK: - Shared ModelContainer holds both entities

    @Test func sharedContainerHoldsRidesAndCrashRecords() throws {
        // Same shape as AppEnvironment.makeLiveRepositories(): one container,
        // both entities. Adding the crash entity must not disturb ride data.
        let schema: [any PersistentModel.Type] = [RideRecord.self, CrashAlertRecordEntity.self]
        let container = try ModelContainer(
            for: Schema(schema),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let rideRepo = SwiftDataRideRepository(context: context)
        let crashRepo = SwiftDataCrashAlertRepository(context: context)

        // Save a ride and a crash record to the SAME context.
        let ride = Ride(
            id: UUID(),
            startedAt: Self.t0,
            endedAt: Self.t0.addingTimeInterval(600),
            points: []
        )
        try rideRepo.save(ride)

        let event = CrashEvent(
            id: UUID(),
            detectedAt: Self.t0,
            utcOffsetMinutes: -240,
            isDrill: true,
            source: "simulator",
            confidence: 1,
            rideId: ride.id,
            state: .sent,
            countdown: nil,
            suppressedUntil: nil,
            locationAtDetection: .unavailable,
            footageRef: nil,
            outcome: .sentNow
        )
        let record = CrashAlertRecord(
            event: event,
            locationAtSend: nil,
            templateVersion: 1,
            renderedText: "WHOOSH DEMO - NOT REAL",
            attempts: [],
            createdAt: Self.t0,
            updatedAt: Self.t0
        )
        try crashRepo.save(record)

        // Both persist independently; neither disturbs the other.
        #expect(try rideRepo.allRides().count == 1)
        #expect(try crashRepo.all().count == 1)
        #expect(try rideRepo.allRides().first?.id == ride.id)
        #expect(try crashRepo.record(id: event.id)?.event.isDrill == true)
    }

    // MARK: - A minimal recording ride session for arming

    /// Build a `RideSessionViewModel` over a fake tracker that can be put into
    /// the `recording` state deterministically.
    static func recordingRideSession(clock: Clock) -> RideSessionViewModel {
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        return RideSessionViewModel(
            tracker: tracker,
            clock: clock,
            repository: InMemoryRideRepository(),
            tuning: RideTuning()
        )
    }
}

private extension RideSessionViewModel {
    /// Start recording for the arming tests. `start()` requires authorization
    /// (the fake tracker is pre-authorized), after which `rideState` is
    /// `recording`.
    func startForTest() {
        start()
    }
}
