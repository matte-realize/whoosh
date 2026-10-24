import Foundation
import Testing
@testable import Whoosh

/// Tests for `SimulatedRouteTracker` (demo-mode task 5, Requirements
/// 5.1/5.3/5.4/5.7/5.8), driven deterministically by `TestClock`.
@MainActor
struct SimulatedRouteTrackerTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    /// A small deterministic script: three moving fixes, then a signal-loss gap
    /// longer than the 8 s loss timeout, then recovery.
    private static func gapScript() -> DemoRideScript {
        DemoRideScript(name: "Gap", points: [
            ScriptedRoutePoint(latitude: 42.0, longitude: -71.0, offsetSeconds: 0, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5),
            ScriptedRoutePoint(latitude: 42.001, longitude: -71.0, offsetSeconds: 10, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5, marker: .signalLossStart),
            ScriptedRoutePoint(latitude: 42.002, longitude: -71.0, offsetSeconds: 15, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5),
            ScriptedRoutePoint(latitude: 42.003, longitude: -71.0, offsetSeconds: 25, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5, marker: .signalLossEnd),
        ])
    }

    // MARK: Authorization (Req 5.1)

    @Test func reportsAuthorizedWhenInUse() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock)
        #expect(tracker.authorizationStatus == .authorizedWhenInUse)
    }

    // MARK: Points arrive in order on schedule (Req 5.1/5.8)

    @Test func pointsArriveInOrderOnSchedule() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock, rideStart: Self.epoch)
        var received: [Double] = []
        tracker.onLocation = { received.append($0.speedMetersPerSecond) }
        tracker.startUpdating(accuracy: .high)

        // Nothing before the first scheduled instant.
        #expect(received.isEmpty)
        clock.advance(by: 0)         // offset 0 point is due at playback t=0
        #expect(received.count == 1)
        clock.advance(by: 25)        // through the end point at offset 25
        // Points at offsets 10 and 15 are inside the signal-loss gap → withheld.
        // So only offsets 0 and 25 are delivered.
        #expect(tracker.emittedCount == 2)
    }

    @Test func deliveredTimestampsFollowScriptOffsets() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock, rideStart: Self.epoch)
        var stamps: [Date] = []
        tracker.onLocation = { stamps.append($0.timestamp) }
        tracker.startUpdating(accuracy: .high)
        clock.advance(by: 100)
        #expect(stamps == [Self.epoch, Self.epoch.addingTimeInterval(25)])
    }

    // MARK: Accelerated playback scales schedule, not data (Req 5.3)

    @Test func acceleratedPlaybackChangesScheduleNotData() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock, speedFactor: 10, rideStart: Self.epoch)
        var stamps: [Date] = []
        tracker.onLocation = { stamps.append($0.timestamp) }
        tracker.startUpdating(accuracy: .high)

        // At 10×, the offset-0 point is due at t=0 and the offset-25 point at
        // t=2.5 s of playback.
        clock.advance(by: 0)
        #expect(tracker.emittedCount == 1)
        clock.advance(by: 2.4)
        #expect(tracker.emittedCount == 1)
        clock.advance(by: 0.1)
        #expect(tracker.emittedCount == 2)
        // The data (timestamps from scripted offsets) is unchanged by speed.
        #expect(stamps == [Self.epoch, Self.epoch.addingTimeInterval(25)])
    }

    // MARK: Stop releases timers (Req 5.7)

    @Test func stopUpdatingHaltsEmissionAndReleasesTimers() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock, rideStart: Self.epoch)
        var received = 0
        tracker.onLocation = { _ in received += 1 }
        tracker.startUpdating(accuracy: .high)
        clock.advance(by: 0)        // first point delivered
        #expect(received == 1)

        tracker.stopUpdating()
        #expect(clock.pendingCount == 0)   // all scheduled emissions cancelled
        clock.advance(by: 100)
        #expect(received == 1)             // no further emissions
        #expect(!tracker.isUpdating)
    }

    // MARK: VM integration — gap trips signal-lost (Req 5.1/5.2)

    @Test func gapTripsSignalLostThroughRideSessionViewModel() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock, rideStart: Self.epoch)
        let repo = InMemoryRideRepository()
        let vm = RideSessionViewModel(
            tracker: tracker,
            clock: clock,
            repository: repo,
            tuning: RideTuning()
        )
        vm.start()
        tracker.startUpdating(accuracy: .high)

        // Deliver the first fix (offset 0).
        clock.advance(by: 0)
        #expect(vm.rideState == .recording)
        #expect(vm.points.count == 1)

        // The gap is offsets 10..<25 (15 s hole > 8 s timeout). After the first
        // fix the loss timer is armed; advancing past the timeout with no fix
        // enters signalLost.
        clock.advance(by: 9)   // t=9: no new fix since t=0 → loss timer (armed at 0, +8) fired at 8
        #expect(vm.rideState == .signalLost)

        // The recovery fix (offset 25) arrives at t=25 and recovers to recording.
        clock.advance(by: 20)  // reach t=25+
        #expect(vm.rideState == .recording)
        #expect(vm.points.count == 2)
    }

    // MARK: VM integration — full route plays in order, pause via controller

    @Test func pauseSegmentEmitsNothingAndRouteGrows() {
        // Use the bundled loop and simulate the controller driving pause/resume
        // at the pause-segment boundaries (task 8 wires this for real).
        let script = DemoRideScript.charlesRiverLoop
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: script, clock: clock, rideStart: Self.epoch)
        let repo = InMemoryRideRepository()
        let vm = RideSessionViewModel(tracker: tracker, clock: clock, repository: repo)
        vm.start()
        tracker.startUpdating(accuracy: .high)

        guard let pauseWindow = script.pauseWindow else {
            Issue.record("expected a pause window")
            return
        }

        // Play up to the pause start, then pause (as the controller would).
        clock.advance(by: pauseWindow.lowerBound)
        let countAtPauseStart = vm.points.count
        vm.pause()
        #expect(vm.rideState == .paused)

        // During the pause the tracker withholds interior points → the paused
        // route does not grow.
        clock.advance(by: pauseWindow.upperBound - pauseWindow.lowerBound - 1)
        #expect(vm.points.count == countAtPauseStart)
        #expect(vm.rideState == .paused)

        // Resume at pause end; the route resumes growing.
        vm.resume()
        #expect(vm.rideState == .recording)
        clock.advance(by: script.totalDuration)   // play out the rest
        #expect(vm.points.count > countAtPauseStart)
    }

    // MARK: No mixing (Req 5.4) — tracker never touches CLLocationManager

    @Test func trackerNeverEmitsWithoutStart() {
        let clock = TestClock(now: Self.epoch)
        let tracker = SimulatedRouteTracker(script: Self.gapScript(), clock: clock)
        var received = 0
        tracker.onLocation = { _ in received += 1 }
        // No startUpdating → nothing scheduled, nothing emitted.
        clock.advance(by: 100)
        #expect(received == 0)
    }
}
