import Foundation
import Testing
@testable import Whoosh

/// Tests for `DemoModeController` (demo-mode task 8; Requirements 1.2, 1.4,
/// 1.6, 4.3, 4.4, 4.6, 9.2, 9.7). Driven deterministically by `TestClock` and
/// fakes. Covers FORCE-1/2/3, persistence, the auto-trigger, and the
/// simulated-ride lifecycle including turning demo off mid-ride (O-DM6).
@MainActor
struct DemoModeControllerTests {
    private static let epoch = Date(timeIntervalSince1970: 2_000_000)

    /// A unique `UserDefaults` suite per test so persistence is isolated.
    private static func isolatedDefaults() -> UserDefaults {
        let name = "demo.controller.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    private struct Harness {
        let controller: DemoModeController
        let alerts: RecordingAlertManager
        let repository: InMemoryRideRepository
        let clock: TestClock
    }

    private static func makeHarness(
        defaults: UserDefaults? = nil,
        clock: TestClock? = nil
    ) -> Harness {
        let defaults = defaults ?? isolatedDefaults()
        let clock = clock ?? TestClock(now: epoch)
        let alerts = RecordingAlertManager()
        let repo = InMemoryRideRepository()
        let controller = DemoModeController(
            defaults: defaults,
            clock: clock,
            alertManager: alerts,
            repository: repo,
            makeSimulatedTracker: { script, factor in
                SimulatedRouteTracker(script: script, clock: clock, speedFactor: factor, rideStart: clock.now())
            },
            makeSimulatedSession: { tracker in
                RideSessionViewModel(tracker: tracker, clock: clock, repository: repo, tuning: RideTuning())
            }
        )
        return Harness(controller: controller, alerts: alerts, repository: repo, clock: clock)
    }

    // MARK: - Toggle persistence (Req 1.2)

    @Test func defaultsOff() {
        let h = Self.makeHarness()
        #expect(!h.controller.isEnabled)
        #expect(!h.controller.badgeVisible)
    }

    @Test func enablingPersistsAndSurvivesRelaunch() {
        let defaults = Self.isolatedDefaults()
        let first = Self.makeHarness(defaults: defaults)
        first.controller.isEnabled = true
        #expect(first.controller.isEnabled)
        #expect(first.controller.badgeVisible)

        // A fresh controller over the same defaults (simulating relaunch) reads
        // the persisted value.
        let second = Self.makeHarness(defaults: defaults)
        #expect(second.controller.isEnabled)
    }

    @Test func disablingPersistsOff() {
        let defaults = Self.isolatedDefaults()
        let h = Self.makeHarness(defaults: defaults)
        h.controller.isEnabled = true
        h.controller.isEnabled = false
        let relaunch = Self.makeHarness(defaults: defaults)
        #expect(!relaunch.controller.isEnabled)
    }

    // MARK: - FORCE-1: single forced alert while stationary / no ride (Req 4.3)

    @Test func forcedAlertFiresOnceWhileStationaryNoRide() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.fireRearAlertOnce()
        #expect(h.alerts.fireCount == 1)
        #expect(h.alerts.firedKinds == [.cautionRearVehicle])
        // No ride exists, so no detection could be logged (no points/rides).
        #expect((try? h.repository.allRides())?.isEmpty == true)
    }

    // MARK: - FORCE-3: forced alert is a no-op while disabled (Req 9.2)

    @Test func forcedAlertNoOpWhileDisabled() {
        let h = Self.makeHarness()
        h.controller.fireRearAlertOnce()
        #expect(h.alerts.fireCount == 0)
    }

    // MARK: - FORCE-2: auto-trigger fires every N and stops (Req 4.4)

    @Test func autoAlertFiresEveryIntervalAndStops() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startAutoRearAlert(every: 10)
        // Fires once immediately.
        #expect(h.alerts.fireCount == 1)
        #expect(h.controller.autoAlertActive)

        h.clock.advance(by: 10)
        #expect(h.alerts.fireCount == 2)
        h.clock.advance(by: 10)
        #expect(h.alerts.fireCount == 3)

        h.controller.stopAutoRearAlert()
        #expect(!h.controller.autoAlertActive)
        h.clock.advance(by: 100)
        #expect(h.alerts.fireCount == 3)   // no more after stop
    }

    @Test func deactivateStopsAutoAlert() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startAutoRearAlert(every: 5)
        #expect(h.alerts.fireCount == 1)

        // Turning demo mode off cancels the auto-trigger (Req 9.7).
        h.controller.isEnabled = false
        #expect(!h.controller.autoAlertActive)
        h.clock.advance(by: 100)
        #expect(h.alerts.fireCount == 1)
    }

    @Test func autoAlertNoOpWhileDisabled() {
        let h = Self.makeHarness()
        h.controller.startAutoRearAlert(every: 5)
        #expect(!h.controller.autoAlertActive)
        #expect(h.alerts.fireCount == 0)
    }

    // MARK: - Simulated-ride lifecycle (Req 5)

    @Test func startSimulatedRideRecordsThroughRealSession() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startSimulatedRide()
        #expect(h.controller.activeSimulatedRide)
        guard let session = h.controller.simulatedSession else {
            Issue.record("expected an active simulated session")
            return
        }
        // First scripted fix is due at playback t=0.
        h.clock.advance(by: 0)
        #expect(session.rideState == .recording)
        #expect(session.points.count >= 1)
    }

    @Test func startSimulatedRideNoOpWhileDisabled() {
        let h = Self.makeHarness()
        h.controller.startSimulatedRide()
        #expect(!h.controller.activeSimulatedRide)
        #expect(h.controller.simulatedSession == nil)
    }

    @Test func scriptedPauseResumeDrivesPausedState() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startSimulatedRide()
        guard let session = h.controller.simulatedSession,
              let window = DemoRideScript.charlesRiverLoop.pauseWindow else {
            Issue.record("expected session + pause window")
            return
        }
        h.clock.advance(by: 0)
        #expect(session.rideState == .recording)
        // Advance to just past the pause start; the controller calls pause().
        h.clock.advance(by: window.lowerBound)
        #expect(session.rideState == .paused)
        // Advance past the pause end; the controller calls resume().
        h.clock.advance(by: window.upperBound - window.lowerBound)
        #expect(session.rideState == .recording)
    }

    @Test func stopSimulatedRideFinalizesAndKeepsDemoRide() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startSimulatedRide()
        h.clock.advance(by: 20)   // play a little so there are points
        h.controller.stopSimulatedRide()
        #expect(!h.controller.activeSimulatedRide)
        let rides = (try? h.repository.allRides()) ?? []
        #expect(rides.count == 1)
        #expect(rides[0].isDemo)
    }

    // MARK: - SIM-6: off mid-ride finalizes-and-keeps (O-DM6, Req 1.6/5.7)

    @Test func turningOffMidSimulatedRideFinalizesAndKeeps() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.startSimulatedRide()
        h.clock.advance(by: 20)
        #expect(h.controller.activeSimulatedRide)

        h.controller.isEnabled = false
        // The ride is finalized (not left half-simulated) and kept in storage.
        #expect(!h.controller.activeSimulatedRide)
        let rides = (try? h.repository.allRides()) ?? []
        #expect(rides.count == 1)
        #expect(rides[0].endedAt != nil)
        #expect(rides[0].isDemo)

        // The tracker stops emitting after teardown — no further scheduled work
        // drives the (now cleared) session.
        h.clock.advance(by: 200)
        #expect(h.controller.simulatedSession == nil)
    }

    // MARK: - Seed / remove (Req 7)

    @Test func seedAndRemoveDemoData() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.seedSampleData()
        let afterSeed = (try? h.repository.allRides()) ?? []
        #expect(!afterSeed.isEmpty)
        #expect(afterSeed.allSatisfy { $0.isDemo })
        #expect(h.controller.existingDemoRideCount == afterSeed.count)

        h.controller.removeDemoData()
        #expect(((try? h.repository.allRides()) ?? []).isEmpty)
        #expect(h.controller.existingDemoRideCount == 0)
    }

    @Test func reseedReportsExistingCountAndCanRemoveFirst() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.seedSampleData()
        let firstCount = h.controller.existingDemoRideCount
        #expect(firstCount > 0)

        // Re-seed removing existing first → no duplicates (O-DM7).
        h.controller.seedSampleData(removingExisting: true)
        #expect(h.controller.existingDemoRideCount == firstCount)
    }

    @Test func removeDemoLeavesRealRides() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        let realRide = Ride(startedAt: Self.epoch, endedAt: Self.epoch.addingTimeInterval(600))
        try? h.repository.save(realRide)
        h.controller.seedSampleData()
        h.controller.removeDemoData()
        let remaining = (try? h.repository.allRides()) ?? []
        #expect(remaining.count == 1)
        #expect(remaining[0].id == realRide.id)
        #expect(!remaining[0].isDemo)
    }

    @Test func dataActionsNoOpWhileDisabled() {
        let h = Self.makeHarness()
        h.controller.seedSampleData()
        #expect(((try? h.repository.allRides()) ?? []).isEmpty)
    }

    // MARK: - State previews (Req 8)

    @Test func showAndDismissStatePreview() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.showStatePreview(.signalLost)
        #expect(h.controller.statePreview == .signalLost)
        h.controller.dismissStatePreview()
        #expect(h.controller.statePreview == nil)
    }

    @Test func statePreviewNoOpWhileDisabled() {
        let h = Self.makeHarness()
        h.controller.showStatePreview(.locationDenied)
        #expect(h.controller.statePreview == nil)
    }

    @Test func deactivateClearsStatePreview() {
        let h = Self.makeHarness()
        h.controller.isEnabled = true
        h.controller.showStatePreview(.crashCountdown)
        h.controller.isEnabled = false
        #expect(h.controller.statePreview == nil)
    }
}
