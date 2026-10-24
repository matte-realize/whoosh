import Foundation
import Testing
@testable import Whoosh

/// Tests for the ride-session state machine (task 10) and the mid-ride
/// persistence safeguard (task 21). Each transition-table row is exercised with
/// `FakeLocationTracker` + `TestClock` + `InMemoryRideRepository`.
@MainActor
struct RideSessionViewModelTests {
    // MARK: Fixtures

    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private static func makeViewModel(
        status: LocationAuthorizationStatus = .authorizedWhenInUse,
        tuning: RideTuning = RideTuning()
    ) -> (RideSessionViewModel, FakeLocationTracker, TestClock, InMemoryRideRepository) {
        let tracker = FakeLocationTracker(authorizationStatus: status)
        let clock = TestClock(now: epoch)
        let repo = InMemoryRideRepository()
        var counter = 0
        let vm = RideSessionViewModel(
            tracker: tracker,
            clock: clock,
            repository: repo,
            tuning: tuning,
            makeID: {
                counter += 1
                return UUID(uuidString: "00000000-0000-0000-0000-00000000000\(counter)")!
            }
        )
        return (vm, tracker, clock, repo)
    }

    /// An acceptable fix at a fixed location with good accuracy.
    private static func goodPoint(
        at instant: Date,
        lat: Double = 42.0,
        lon: Double = -71.0,
        accuracy: Double = 5,
        speed: Double = 5
    ) -> RoutePoint {
        RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: instant,
            speedMetersPerSecond: speed,
            horizontalAccuracyMeters: accuracy
        )
    }

    // MARK: - Row 1: idle + start (authorized) -> recording

    @Test func row1_startAuthorizedBeginsRecording() {
        let (vm, tracker, _, _) = Self.makeViewModel(status: .authorizedWhenInUse)
        vm.start()
        #expect(vm.rideState == .recording)
        #expect(tracker.isUpdating)
        #expect(tracker.lastAccuracy == RideTuning().accuracy)
        #expect(vm.finishedRide == nil)
    }

    // MARK: - Row 2: idle + start (not authorized)

    @Test func row2_startNotDeterminedRequestsAuthAndWaits() {
        let (vm, tracker, _, _) = Self.makeViewModel(status: .notDetermined)
        vm.start()
        // No ride yet: still idle, auth requested.
        #expect(vm.rideState == .idle)
        #expect(tracker.requestAuthorizationCount == 1)
        #expect(!tracker.isUpdating)

        // Once granted, the ride starts.
        tracker.changeAuthorization(.authorizedWhenInUse)
        #expect(vm.rideState == .recording)
        #expect(tracker.isUpdating)
    }

    @Test func row2_startDeniedShowsPermissionNeeded() {
        let (vm, tracker, _, _) = Self.makeViewModel(status: .denied)
        vm.start()
        #expect(vm.rideState == .idle)
        #expect(vm.banner == .permissionNeeded)
        #expect(!tracker.isUpdating)
    }

    @Test func row2_notDeterminedThenDeniedShowsPermissionNeeded() {
        let (vm, tracker, _, _) = Self.makeViewModel(status: .notDetermined)
        vm.start()
        tracker.changeAuthorization(.denied)
        #expect(vm.rideState == .idle)
        #expect(vm.banner == .permissionNeeded)
    }

    // MARK: - Row 3: recording + acceptable fix -> recording (append, re-arm)

    @Test func row3_acceptableFixAppendsAndRearmsTimer() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        #expect(vm.points.count == 1)
        #expect(vm.rideState == .recording)

        // Re-armed: advancing just under a fresh timeout from the fix does not
        // trigger signal loss (if it weren't re-armed it would already fire).
        clock.advance(by: RideTuning().signalLossTimeout - 1)
        #expect(vm.rideState == .recording)
    }

    // MARK: - Row 4: recording + unacceptable fix -> recording (discard, re-arm)

    @Test func row4_badAccuracyDiscardedButTimerRearmed() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        let bad = Self.goodPoint(at: clock.now(), accuracy: 999)
        tracker.emit(bad)
        #expect(vm.points.isEmpty)
        #expect(vm.rideState == .recording)
        // Timer re-armed even though the point was discarded.
        clock.advance(by: RideTuning().signalLossTimeout - 1)
        #expect(vm.rideState == .recording)
    }

    @Test func row4_negativeAccuracyDiscarded() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now(), accuracy: -1))
        #expect(vm.points.isEmpty)
    }

    // MARK: - Row 5: recording + pause -> paused

    @Test func row5_pauseStopsAppendingAndAccumulates() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        clock.advance(by: 10)
        vm.pause()
        #expect(vm.rideState == .paused)
        // Paused ignores incoming points.
        tracker.emit(Self.goodPoint(at: clock.now()))
        #expect(vm.points.isEmpty)
        #expect(vm.activeDuration(at: clock.now()) == 10)
    }

    // MARK: - Row 6: paused + resume -> recording

    @Test func row6_resumeReentersRecording() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        vm.pause()
        vm.resume()
        #expect(vm.rideState == .recording)
        tracker.emit(Self.goodPoint(at: clock.now()))
        #expect(vm.points.count == 1)
    }

    // MARK: - Row 7: paused + location point -> paused (ignore)

    @Test func row7_pausedIgnoresPoints() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        vm.pause()
        tracker.emitPoints([Self.goodPoint(at: clock.now()), Self.goodPoint(at: clock.now())])
        #expect(vm.points.isEmpty)
        #expect(vm.rideState == .paused)
    }

    // MARK: - Row 8: recording + loss-timer fires -> signalLost

    @Test func row8_lossTimerFiresEntersSignalLost() {
        let (vm, _, clock, _) = Self.makeViewModel()
        vm.start()
        clock.advance(by: RideTuning().signalLossTimeout + 0.1)
        #expect(vm.rideState == .signalLost)
        #expect(vm.banner == .signalLost)
    }

    // MARK: - Row 9: signalLost + acceptable fix -> recording (recover)

    @Test func row9_acceptableFixRecoversFromSignalLost() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        clock.advance(by: RideTuning().signalLossTimeout + 0.1)
        #expect(vm.rideState == .signalLost)
        tracker.emit(Self.goodPoint(at: clock.now()))
        #expect(vm.rideState == .recording)
        #expect(vm.banner == nil)
        #expect(vm.points.count == 1)
    }

    // MARK: - Row 10: signalLost + pause -> paused

    @Test func row10_pauseFromSignalLost() {
        let (vm, _, clock, _) = Self.makeViewModel()
        vm.start()
        clock.advance(by: RideTuning().signalLossTimeout + 0.1)
        #expect(vm.rideState == .signalLost)
        vm.pause()
        #expect(vm.rideState == .paused)
    }

    // MARK: - Row 11: recording + authorization revoked -> signalLost*

    @Test func row11_revokedMidRideEntersSignalLostAndCanStopSave() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        clock.advance(by: 5)
        tracker.changeAuthorization(.denied)
        #expect(vm.rideState == .signalLost)
        #expect(vm.banner == .permissionRevoked)

        // No auto-recovery: a later acceptable fix must NOT resume appending.
        tracker.emit(Self.goodPoint(at: clock.now()))
        #expect(vm.rideState == .signalLost)
        #expect(vm.points.count == 1)

        // User can still stop & save.
        vm.stop()
        #expect(vm.rideState == .finished)
        let saved = try? repo.allRides()
        #expect(saved?.count == 1)
    }

    // MARK: - Row 12: any active + stop -> finished (finalize/persist)

    @Test func row12_stopFromRecordingFinalizesAndPersists() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.0))
        clock.advance(by: 20)
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.001))
        vm.stop()
        #expect(vm.rideState == .finished)
        #expect(vm.finishedRide != nil)
        #expect(tracker.isUpdating == false)   // stopUpdating called
        let saved = (try? repo.allRides()) ?? []
        #expect(saved.filter { $0.endedAt != nil }.count == 1)
    }

    @Test func row12_stopFromPausedFinalizes() {
        let (vm, _, _, repo) = Self.makeViewModel()
        vm.start()
        vm.pause()
        vm.stop()
        #expect(vm.rideState == .finished)
        #expect(((try? repo.allRides()) ?? []).count == 1)
    }

    @Test func row12_stopFromSignalLostFinalizes() {
        let (vm, _, clock, repo) = Self.makeViewModel()
        vm.start()
        clock.advance(by: RideTuning().signalLossTimeout + 0.1)
        #expect(vm.rideState == .signalLost)
        vm.stop()
        #expect(vm.rideState == .finished)
        #expect(((try? repo.allRides()) ?? []).count == 1)
    }

    // MARK: - Row 13: finished + any -> finished (no-op)

    @Test func row13_finishedIsTerminalNoOp() {
        let (vm, _, _, repo) = Self.makeViewModel()
        vm.start()
        vm.stop()
        #expect(vm.rideState == .finished)
        vm.start(); vm.pause(); vm.resume(); vm.stop()
        #expect(vm.rideState == .finished)
        #expect(((try? repo.allRides()) ?? []).count == 1)   // no second ride
    }

    // MARK: - Row 14: idle + pause/resume/stop -> idle (no-op)

    @Test func row14_undefinedTransitionsFromIdleAreNoOps() {
        let (vm, tracker, _, repo) = Self.makeViewModel()
        vm.pause()
        vm.resume()
        vm.stop()
        #expect(vm.rideState == .idle)
        #expect(!tracker.isUpdating)
        #expect(((try? repo.allRides()) ?? []).isEmpty)
    }

    // MARK: - Active duration excludes paused spans

    @Test func activeDurationExcludesPausedSpans() {
        let (vm, _, clock, _) = Self.makeViewModel()
        vm.start()                       // t=0
        clock.advance(by: 30)            // record 30s
        vm.pause()                       // accumulate 30
        clock.advance(by: 100)           // paused 100s (excluded)
        vm.resume()                      // new span
        clock.advance(by: 20)            // record 20s
        #expect(vm.activeDuration(at: clock.now()) == 50)
        vm.stop()
        #expect(vm.finishedRide?.summary.activeDuration == 50)
    }

    // MARK: - Signal-loss timeout and recovery with TestClock

    @Test func signalLossTimeoutThenRecovery() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        clock.advance(by: RideTuning().signalLossTimeout + 0.5)
        #expect(vm.rideState == .signalLost)
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.0005))
        #expect(vm.rideState == .recording)
        #expect(vm.banner == nil)
    }

    // MARK: - Accuracy filter

    @Test func accuracyFilterBoundary() {
        let tuning = RideTuning(maxAcceptableAccuracyMeters: 30)
        let (vm, tracker, clock, _) = Self.makeViewModel(tuning: tuning)
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now(), accuracy: 30))    // == threshold, accepted
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.0001, accuracy: 31))  // rejected
        #expect(vm.points.count == 1)
    }

    // MARK: - Jump filter

    @Test func jumpFilterRejectsImplausibleSpeed() {
        let tuning = RideTuning(maxPlausibleSpeedMetersPerSecond: 35)
        let (vm, tracker, clock, _) = Self.makeViewModel(tuning: tuning)
        vm.start()
        let t0 = clock.now()
        tracker.emit(Self.goodPoint(at: t0, lat: 42.0, lon: -71.0))
        // ~1.1 km away 1 second later => ~1100 m/s, way over the cap.
        tracker.emit(Self.goodPoint(at: t0.addingTimeInterval(1), lat: 42.01, lon: -71.0))
        #expect(vm.points.count == 1)
    }

    @Test func jumpFilterAllowsPlausibleMovement() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        let t0 = clock.now()
        tracker.emit(Self.goodPoint(at: t0, lat: 42.0, lon: -71.0))
        // ~11 m in 2 s => ~5.5 m/s, plausible.
        tracker.emit(Self.goodPoint(at: t0.addingTimeInterval(2), lat: 42.0001, lon: -71.0))
        #expect(vm.points.count == 2)
    }

    // MARK: - Undefined transitions no-op (double-start while recording)

    @Test func startWhileRecordingIsNoOp() {
        let (vm, _, _, repo) = Self.makeViewModel()
        vm.start()
        let firstID = vm.finishedRide?.id
        vm.start()   // ignored
        #expect(vm.rideState == .recording)
        _ = firstID
        vm.stop()
        #expect(((try? repo.allRides()) ?? []).count == 1)
    }

    // MARK: - Zero-point finalize gives zeroed summary

    @Test func zeroPointFinalizeGivesZeroedSummary() {
        let (vm, _, _, _) = Self.makeViewModel()
        vm.start()
        vm.stop()
        #expect(vm.finishedRide?.summary == RideSummary.zero || vm.finishedRide?.summary.distanceMeters == 0)
        #expect(vm.finishedRide?.summary.distanceMeters == 0)
        #expect(vm.finishedRide?.summary.averageSpeedMetersPerSecond == 0)
    }

    // MARK: - Stop persists exactly one ride & releases tracking

    @Test func stopPersistsExactlyOneRideAndStopsUpdating() {
        let (vm, tracker, _, repo) = Self.makeViewModel()
        vm.start()
        #expect(tracker.isUpdating)
        vm.stop()
        #expect(!tracker.isUpdating)
        #expect(((try? repo.allRides()) ?? []).count == 1)
    }

    // MARK: - Task 21: incremental persistence and recovery

    @Test func snapshotPersistedEveryNPoints() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        // Emit exactly snapshotEveryPoints acceptable points.
        for i in 0..<RideSessionViewModel.snapshotEveryPoints {
            tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.0 + Double(i) * 0.0001))
        }
        let stored = (try? repo.allRides()) ?? []
        // An in-progress ride (endedAt == nil) was saved.
        #expect(stored.contains { $0.endedAt == nil && $0.points.count == RideSessionViewModel.snapshotEveryPoints })
    }

    @Test func periodicSnapshotTimerPersists() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        clock.advance(by: RideSessionViewModel.snapshotEverySeconds + 0.1)
        let stored = (try? repo.allRides()) ?? []
        #expect(stored.contains { $0.endedAt == nil })
    }

    @Test func persistSnapshotManuallySavesInProgressRide() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        vm.persistSnapshot()
        let stored = (try? repo.allRides()) ?? []
        #expect(stored.contains { $0.endedAt == nil && $0.points.count == 1 })
    }

    @Test func recoverInterruptedRideFindsUnfinished() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        vm.persistSnapshot()
        let recovered = vm.recoverInterruptedRide()
        #expect(recovered != nil)
        #expect(recovered?.endedAt == nil)
    }

    @Test func finalizeRecoveredRideProducesFinishedRide() {
        let (vm, tracker, clock, repo) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.0))
        clock.advance(by: 10)
        tracker.emit(Self.goodPoint(at: clock.now(), lat: 42.001))
        vm.persistSnapshot()
        guard let unfinished = vm.recoverInterruptedRide() else {
            Issue.record("expected an unfinished ride to recover")
            return
        }
        let finalized = vm.finalizeRecoveredRide(unfinished)
        #expect(finalized?.endedAt != nil)
        let stored = (try? repo.allRides()) ?? []
        #expect(stored.allSatisfy { $0.endedAt != nil })
    }

    @Test func finishedRidesExcludesInProgressSnapshots() {
        let (vm, tracker, clock, _) = Self.makeViewModel()
        vm.start()
        tracker.emit(Self.goodPoint(at: clock.now()))
        vm.persistSnapshot()               // in-progress snapshot saved
        #expect(vm.finishedRides().isEmpty) // not shown as finished
        vm.stop()                           // now finished
        #expect(vm.finishedRides().count == 1)
    }

    // MARK: - Task 24: low-power / thermal degradation (Requirement 11.2)

    private static func makeViewModelWithPower(
        tuning: RideTuning = RideTuning(accuracy: .high),
        monitor: FakePowerMonitor
    ) -> (RideSessionViewModel, FakeLocationTracker) {
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        let clock = TestClock(now: epoch)
        let repo = InMemoryRideRepository()
        let vm = RideSessionViewModel(
            tracker: tracker,
            clock: clock,
            repository: repo,
            tuning: tuning,
            powerMonitor: monitor
        )
        return (vm, tracker)
    }

    @Test func lowPowerModeDegradesToBalancedAtStart() {
        let monitor = FakePowerMonitor(lowPowerMode: true)
        let (vm, tracker) = Self.makeViewModelWithPower(monitor: monitor)
        vm.start()
        // Requested .high but Low Power Mode forces .balanced for the request.
        #expect(tracker.lastAccuracy == .balanced)
        #expect(vm.isUsingReducedAccuracy)
        #expect(monitor.isMonitoring)
    }

    @Test func normalPowerKeepsRequestedAccuracy() {
        let monitor = FakePowerMonitor(lowPowerMode: false)
        let (vm, tracker) = Self.makeViewModelWithPower(monitor: monitor)
        vm.start()
        #expect(tracker.lastAccuracy == .high)
        #expect(!vm.isUsingReducedAccuracy)
    }

    @Test func enteringLowPowerMidRideReappliesBalanced() {
        let monitor = FakePowerMonitor(lowPowerMode: false)
        let (vm, tracker) = Self.makeViewModelWithPower(monitor: monitor)
        vm.start()
        #expect(tracker.lastAccuracy == .high)
        let startsBefore = tracker.startUpdatingCount
        // Device enters Low Power Mode mid-ride.
        monitor.isLowPowerModeEnabled = true
        monitor.notifyChange()
        #expect(tracker.lastAccuracy == .balanced)
        #expect(tracker.startUpdatingCount == startsBefore + 1)
        #expect(vm.isUsingReducedAccuracy)
        // Ride keeps recording — never crashes or stops.
        #expect(vm.rideState == .recording)
    }

    @Test func thermalThrottlingDegradesAccuracy() {
        let monitor = FakePowerMonitor(thermallyThrottled: true)
        let (vm, tracker) = Self.makeViewModelWithPower(monitor: monitor)
        vm.start()
        #expect(tracker.lastAccuracy == .balanced)
        #expect(vm.isUsingReducedAccuracy)
    }

    @Test func powerChangeWhileIdleDoesNotStartTracking() {
        let monitor = FakePowerMonitor(lowPowerMode: false)
        let (_, tracker) = Self.makeViewModelWithPower(monitor: monitor)
        // No ride started.
        monitor.isLowPowerModeEnabled = true
        monitor.notifyChange()
        #expect(!tracker.isUpdating)
        #expect(tracker.startUpdatingCount == 0)
    }

    @Test func stopReleasesPowerMonitor() {
        let monitor = FakePowerMonitor(lowPowerMode: true)
        let (vm, _) = Self.makeViewModelWithPower(monitor: monitor)
        vm.start()
        #expect(monitor.isMonitoring)
        vm.stop()
        #expect(!monitor.isMonitoring)
    }
}
