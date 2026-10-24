import Foundation
import Testing
@testable import Whoosh

/// Composition-root wiring tests for demo mode (demo-mode task 9; Requirements
/// 5.1, 5.4, 5.5, 9.1, 9.3). Builds `AppEnvironment.preview(...)` over fakes and
/// a `TestClock` so the off path (identity) and the simulated-ride branch are
/// both verifiable without a device.
@MainActor
struct DemoCompositionTests {
    private static let epoch = Date(timeIntervalSince1970: 3_000_000)

    private static func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "demo.composition.tests.\(UUID().uuidString)") ?? .standard
    }

    // MARK: - OFF-1: off path is the identity path (Req 9.1)

    @Test func offPathBadgeHiddenAndNoSimulatedSession() {
        let env = AppEnvironment.preview(
            seeded: false,
            clock: TestClock(now: Self.epoch),
            defaults: Self.isolatedDefaults()
        )
        #expect(!env.demo.isEnabled)
        #expect(!env.demo.badgeVisible)
        #expect(env.demo.simulatedSession == nil)

        // With demo off, makeRideSession returns a normal session (never the
        // demo's simulated one), so the off path equals today's wiring.
        let session = env.makeRideSession()
        #expect(env.demo.simulatedSession == nil)
        session.start()
        // A normal fake-tracker session does not auto-emit scripted points.
        #expect(session.points.isEmpty)
    }

    @Test func offPathDoesNotFireAlertFromAnyDemoPath() {
        let env = AppEnvironment.preview(
            seeded: false,
            clock: TestClock(now: Self.epoch),
            defaults: Self.isolatedDefaults()
        )
        // Every demo intent is a no-op while off: fireRearAlertOnce, auto-alert,
        // simulated ride, seed/remove, previews.
        env.demo.fireRearAlertOnce()
        env.demo.startAutoRearAlert(every: 1)
        env.demo.startSimulatedRide()
        env.demo.seedSampleData()
        env.demo.showStatePreview(.signalLost)

        #expect(!env.demo.activeSimulatedRide)
        #expect(!env.demo.autoAlertActive)
        #expect(env.demo.statePreview == nil)
        #expect(((try? env.repository.allRides()) ?? []).isEmpty)
    }

    // MARK: - SIM-4: simulated-ride session is the demo one (no mixing, Req 5.4)

    @Test func simulatedRideSessionIsDemoOwnedAndScripted() {
        let clock = TestClock(now: Self.epoch)
        let env = AppEnvironment.preview(
            seeded: false,
            clock: clock,
            defaults: Self.isolatedDefaults()
        )
        env.demo.isEnabled = true
        env.demo.startSimulatedRide()

        // makeRideSession returns the demo-owned simulated session, not a fresh
        // CoreLocation/Fake one — one ride ⇒ one (scripted) tracker.
        guard let demoSession = env.demo.simulatedSession else {
            Issue.record("expected a simulated session")
            return
        }
        #expect(env.makeRideSession() === demoSession)

        // It plays scripted points on the clock (a plain fake tracker would not).
        clock.advance(by: 0)
        #expect(demoSession.rideState == .recording)
        #expect(demoSession.points.count >= 1)
    }

    // MARK: - SIM-5: finished simulated ride is isDemo and skipped by sync (Req 5.5/9.3)

    @Test func finishedSimulatedRideIsDemoAndSkippedBySync() async {
        let clock = TestClock(now: Self.epoch)
        let env = AppEnvironment.preview(
            seeded: false,
            clock: clock,
            defaults: Self.isolatedDefaults()
        )
        env.demo.isEnabled = true
        env.demo.startSimulatedRide()
        clock.advance(by: 30)        // play a little
        env.demo.stopSimulatedRide()

        let rides = (try? env.repository.allRides()) ?? []
        #expect(rides.count == 1)
        #expect(rides[0].isDemo)

        // A SyncCoordinator with sync ENABLED must never upload a demo ride.
        let service = FakeRideSyncService(isEnabled: true)
        let coordinator = SyncCoordinator(
            service: service,
            repository: env.repository,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        await coordinator.rideDidFinish(rides[0])
        #expect(service.uploadedRides.isEmpty)
    }
}
