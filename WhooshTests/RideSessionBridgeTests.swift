import Foundation
import Testing
@testable import Whoosh

/// Tests for `RideSessionBridge` (crash-response task 15): it publishes a
/// read-only `RideContext` over the real `RideSessionViewModel` and starts/stops
/// the detector as `CrashArming` flips. Uses the real ride engine with
/// `FakeLocationTracker` + `TestClock` + `InMemoryRideRepository`, so the ride
/// internals are unchanged (the existing ride tests stay green).
@MainActor
struct RideSessionBridgeTests {
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    private static func makeRide(
        status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> (RideSessionViewModel, FakeLocationTracker, TestClock) {
        let tracker = FakeLocationTracker(authorizationStatus: status)
        let clock = TestClock(now: epoch)
        let repo = InMemoryRideRepository()
        var counter = 0
        let vm = RideSessionViewModel(
            tracker: tracker, clock: clock, repository: repo,
            makeID: {
                counter += 1
                return UUID(uuidString: "00000000-0000-0000-0000-00000000000\(counter)")!
            }
        )
        return (vm, tracker, clock)
    }

    private static func goodPoint(at instant: Date, lat: Double = 42.0, lon: Double = -71.0) -> RoutePoint {
        RoutePoint(latitude: lat, longitude: lon, timestamp: instant, speedMetersPerSecond: 5, horizontalAccuracyMeters: 5)
    }

    /// Fully-armed non-ride inputs: enabled, consent current, label, one contact.
    private static func armedInputs() -> RideSessionBridge.ArmingInputs {
        RideSessionBridge.ArmingInputs(enabled: true, consentCurrent: true, riderLabelPresent: true, reachableContactCount: 1)
    }

    // MARK: - RideContext projection

    @Test func projectsRideStateAndFix() {
        let (vm, tracker, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        #expect(bridge.isRideActive == false)
        #expect(bridge.isRecordingOrSignalLost == false)
        #expect(bridge.latestAcceptedFix == nil)

        vm.start()
        tracker.emit(Self.goodPoint(at: Self.epoch.addingTimeInterval(1)))
        #expect(bridge.isRideActive)
        #expect(bridge.isRecordingOrSignalLost)
        #expect(bridge.latestAcceptedFix?.latitude == 42.0)
        #expect(bridge.currentRideID != nil)
    }

    // MARK: - Arming on ride state (O10): recording/signalLost armed; paused/idle/finished disarmed

    @Test func armsWhileRecording() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        bridge.start()
        #expect(bridge.isDetectorArmed == false)  // idle
        vm.start()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        #expect(detector.isMonitoring)
    }

    @Test func disarmsWhilePaused() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        vm.start()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        vm.pause()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed == false)
        #expect(detector.isMonitoring == false)
    }

    @Test func armsAgainOnResume() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        vm.start(); bridge.reevaluateArming()
        vm.pause(); bridge.reevaluateArming()
        vm.resume(); bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
    }

    @Test func disarmsWhenFinished() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        vm.start(); bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        vm.stop()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed == false)
    }

    @Test func armsWhileSignalLost() {
        let (vm, tracker, clock) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        vm.start()
        // Drive to signalLost by letting the loss timer fire.
        clock.advance(by: RideTuning().signalLossTimeout + 1)
        #expect(vm.rideState == .signalLost)
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        _ = tracker
    }

    // MARK: - Non-ride inputs flip arming

    @Test func disarmedWhenFeatureOff() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let inputs = RideSessionBridge.ArmingInputs(enabled: false, consentCurrent: true, riderLabelPresent: true, reachableContactCount: 1)
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: { inputs })
        vm.start()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed == false)
    }

    @Test func disarmedWhenNoReachableContact() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let inputs = RideSessionBridge.ArmingInputs(enabled: true, consentCurrent: true, riderLabelPresent: true, reachableContactCount: 0)
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: { inputs })
        vm.start()
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed == false)
    }

    @Test func consentChangeReevaluatesArming() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        var consentCurrent = true
        let bridge = RideSessionBridge(
            rideViewModel: vm, detector: detector,
            armingInputs: {
                RideSessionBridge.ArmingInputs(enabled: true, consentCurrent: consentCurrent, riderLabelPresent: true, reachableContactCount: 1)
            }
        )
        vm.start(); bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        consentCurrent = false  // consent revoked
        bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed == false)
    }

    // MARK: - Observation path arms on ride-state change without explicit call

    @Test func observationStartsDetectorWhenRecordingBegins() async {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        bridge.start()  // installs observation tracking
        #expect(bridge.isDetectorArmed == false)
        vm.start()      // rideState change should trigger onChange → reevaluate
        for _ in 0..<5 { await Task.yield() }
        #expect(bridge.isDetectorArmed)
    }

    // MARK: - stop() disarms

    @Test func stopDisarmsDetector() {
        let (vm, _, _) = Self.makeRide()
        let detector = FakeCrashDetector()
        let bridge = RideSessionBridge(rideViewModel: vm, detector: detector, armingInputs: Self.armedInputs)
        vm.start(); bridge.reevaluateArming()
        #expect(bridge.isDetectorArmed)
        bridge.stop()
        #expect(bridge.isDetectorArmed == false)
        #expect(detector.stopCount >= 1)
    }
}
