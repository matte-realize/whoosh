import Foundation
import Testing
@testable import Whoosh

/// Tests for the demo path (crash-response task 23): `DebugCrashSimulator`
/// behaviour, developer-tools toggle gating in `EmergencySetupViewModel`, and
/// DRILL-1 — a simulated crash runs the real coordinator with the `drill`
/// template, hides Call 911 (via `isDrill`), and does not consume the
/// real-alert per-ride cap. Fakes only; time via `TestClock`.
@MainActor
struct DebugCrashSimulatorTests {
    typealias Fixtures = CrashResponseCoordinatorTests
    static let t0 = Fixtures.t0

    // MARK: - DebugCrashSimulator unit behaviour

    @Test func emitsDrillSignalOnlyWhileMonitoring() {
        let clock = TestClock(now: Self.t0)
        let simulator = DebugCrashSimulator(clock: clock)
        var received: [CrashSignal] = []
        simulator.onSignal = { received.append($0) }

        // Not started ⇒ no delivery.
        simulator.simulateCrash()
        #expect(received.isEmpty)

        simulator.start()
        simulator.simulateCrash()
        #expect(received.count == 1)
        #expect(received.first?.isDrill == true)
        #expect(received.first?.source == DebugCrashSimulator.sourceLabel)
        #expect(received.first?.timestamp == Self.t0)

        simulator.stop()
        simulator.simulateCrash()
        #expect(received.count == 1)   // stopped ⇒ no further delivery
    }

    @Test func canSimulateRealCrashPathWhenRequested() {
        let clock = TestClock(now: Self.t0)
        let simulator = DebugCrashSimulator(clock: clock)
        var received: [CrashSignal] = []
        simulator.onSignal = { received.append($0) }
        simulator.start()
        simulator.simulateCrash(isDrill: false)
        #expect(received.first?.isDrill == false)
    }

    @Test func neverEmitsOnItsOwn() {
        let clock = TestClock(now: Self.t0)
        let simulator = DebugCrashSimulator(clock: clock)
        var count = 0
        simulator.onSignal = { _ in count += 1 }
        simulator.start()
        // Advancing the clock (no simulateCrash call) must not emit.
        clock.advance(by: 1000)
        #expect(count == 0)
    }

    // MARK: - Developer-tools toggle gating

    @Test func toggleGatesSimulateCrashHook() {
        let settingsStore = InMemoryCrashAlertSettingsStore()
        let vm = EmergencySetupViewModel(
            contactStore: InMemoryEmergencyContactStore(),
            settingsStore: settingsStore
        )
        var simulateCalls = 0
        vm.onSimulateCrash = { simulateCalls += 1 }

        // Off by default ⇒ the hook is a no-op even if invoked.
        #expect(!vm.developerToolsEnabled)
        vm.simulateCrash()
        #expect(simulateCalls == 0)

        // Turning it on persists and lets the hook fire.
        vm.developerToolsEnabled = true
        #expect(settingsStore.current().developerToolsEnabled)
        vm.simulateCrash()
        #expect(simulateCalls == 1)
    }

    @Test func toggleStatePersistsAndReloads() {
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(developerToolsEnabled: true)
        )
        let vm = EmergencySetupViewModel(
            contactStore: InMemoryEmergencyContactStore(),
            settingsStore: settingsStore
        )
        #expect(vm.developerToolsEnabled)
    }

    // MARK: - DRILL-1: simulator ⇒ real workflow, drill template, cap unaffected

    @Test func drill1_simulatorDrivesRealWorkflowWithDrillTemplateAndNoCap() async {
        let ref = UUID()
        let contact = EmergencyContact(id: ref, label: "Mom", e164: "+16175550123", verification: .reachable)
        // Build a coordinator wired to a real DebugCrashSimulator as its detector.
        let clock = TestClock(now: Self.t0)
        let simulator = DebugCrashSimulator(clock: clock)
        let notifier = FakeCrashNotifier()
        notifier.sendBehavior = .success(
            recipients: [CrashRecipientResult(recipientRef: ref, status: .sent, segments: 3, updatedAt: Self.t0)],
            deduplicated: false
        )
        let contactStore = InMemoryEmergencyContactStore()
        try? contactStore.add(contact)
        let consentStore = InMemoryConsentStore()
        consentStore.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)
        let settingsStore = InMemoryCrashAlertSettingsStore(
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex", developerToolsEnabled: true)
        )
        let coordinator = CrashResponseCoordinator(
            detector: simulator,
            rideContext: FakeRideContext(isRideActive: true, isRecordingOrSignalLost: true, latestAcceptedFix: nil, currentRideID: UUID()),
            footageBuffer: FakeFootageBuffer(),
            notifier: notifier,
            scheduler: FakeCrashNotificationScheduler(),
            feedback: FakeCountdownFeedback(),
            connectivity: { let c = FakeConnectivityMonitor(isOnline: true); c.start(); return c }(),
            contactStore: contactStore,
            consentStore: consentStore,
            settingsStore: settingsStore,
            repository: InMemoryCrashAlertRepository(),
            clock: clock
        )
        simulator.start()

        // Simulate crash ⇒ real countdown begins, flagged as a drill.
        simulator.simulateCrash()
        #expect(coordinator.eventState == .countdown)
        #expect(coordinator.isDrill)

        coordinator.sendNow()
        await Fixtures.drain()
        #expect(coordinator.eventState == .sent)
        // The request used the drill template.
        #expect(notifier.sendRequests.first?.kind == .drill)
        // The real-alert per-ride cap is not consumed by a drill.
        #expect(coordinator.machine.perRideSentCount == 0)
    }
}
