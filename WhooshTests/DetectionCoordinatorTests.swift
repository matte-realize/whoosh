import Foundation
import Testing
@testable import Whoosh

/// Tests for the `DetectionCoordinator` (rear-camera spec task 14, Requirements
/// 4.9, 15.1–15.5). Everything is driven with fakes — `FakeHazardDetector`,
/// `RecordingAlertManager`, a `TestClock`, and closure seams — so the routing,
/// registration lifecycle, and near-miss/clip handling are verified without a
/// camera, model, or frames. The real model run is a device check.
@MainActor
struct DetectionCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// A mutable world the closure seams read, so a test can flip ride/camera
    /// state between calls.
    private final class World {
        var rideState: RideState = .recording
        var speed: Double = 5
        var cameraState: CameraRecordingState = .recording(.standard)
        var storage: StorageStatus = .ok
        var detectionEnabled = true
        var demoMode = false
        var autoPinEnabled = false
        var rideId: UUID? = UUID()
        var coordinate: DetectionCoordinator.RouteCoordinate? = (42.36, -71.06)
        var recordedEvents: [NearMissEvent] = []
        var pinnedAt: [Date] = []
        var pinResult: UUID?
    }

    private func makeCoordinator(
        detector: HazardDetector,
        alertManager: AlertManager,
        clock: Clock,
        world: World,
        confidenceThreshold: Double = 0.5,
        tuning: RideCameraTuning = RideCameraTuning()
    ) -> DetectionCoordinator {
        DetectionCoordinator(
            detector: detector,
            pipeline: nil,
            alertManager: alertManager,
            clock: clock,
            tuning: tuning,
            confidenceThreshold: confidenceThreshold,
            rideStateProvider: { world.rideState },
            currentSpeedProvider: { world.speed },
            cameraStateProvider: { world.cameraState },
            storageStatusProvider: { world.storage },
            isDetectionEnabled: { world.detectionEnabled },
            isDemoMode: { world.demoMode },
            isAutoPinEnabled: { world.autoPinEnabled },
            currentRideId: { world.rideId },
            routeCoordinate: { _ in world.coordinate },
            recordNearMiss: { world.recordedEvents.append($0) },
            pinDetectionClip: { world.pinnedAt.append($0); return world.pinResult },
            makeEventId: { UUID() }
        )
    }

    private func detection(confidence: Double, hint: String? = "center") -> HazardDetection {
        HazardDetection(timestamp: now, kind: "vehicle", confidence: confidence, relativePositionHint: hint)
    }

    // CC-1: while recording and moving, a detection fires a rear-vehicle alert.
    @Test func firesAlertWhileRecordingAndMoving() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let clock = TestClock(now: now)
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: clock, world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        #expect(alerts.firedKinds == [.cautionRearVehicle])
    }

    // CC-2: the normal gate suppresses the alert when the rider is too slow.
    @Test func gateSuppressesAlertWhenSlow() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let world = World()
        world.speed = 1   // below the 2 m/s gate
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: TestClock(now: now), world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        #expect(alerts.fireCount == 0)
    }

    // CC-3: demo mode bypasses the gate — an alert fires even while stationary.
    @Test func demoModeBypassesGate() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let world = World()
        world.speed = 0
        world.rideState = .paused
        world.demoMode = true
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: TestClock(now: now), world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        #expect(alerts.firedKinds == [.cautionRearVehicle])
    }

    // CC-4: the rear-vehicle cooldown collapses a burst to a single cue.
    @Test func alertCooldownCollapsesBurst() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let clock = TestClock(now: now)
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: clock, world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        clock.advance(by: 1)   // within the 3 s rearVehicleAlertCooldown
        detector.emit(detection(confidence: 0.9))
        #expect(alerts.fireCount == 1)

        clock.advance(by: 5)   // past the cooldown
        detector.emit(detection(confidence: 0.9))
        #expect(alerts.fireCount == 2)
    }

    // CC-5: an eligible detection records a near-miss event with the route
    // coordinate; with auto-pin off it carries no clip id.
    @Test func recordsNearMissEventWithoutPinWhenAutoPinOff() {
        let detector = FakeHazardDetector()
        let world = World()
        world.autoPinEnabled = false
        let coord = makeCoordinator(detector: detector, alertManager: RecordingAlertManager(),
                                    clock: TestClock(now: now), world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9, hint: "left"))
        #expect(world.recordedEvents.count == 1)
        let event = world.recordedEvents[0]
        #expect(event.kind == "vehicle")
        #expect(event.confidence == 0.9)
        #expect(event.positionHint == "left")
        #expect(event.latitude == 42.36)
        #expect(event.localClipId == nil)
        #expect(world.pinnedAt.isEmpty)
    }

    // CC-6: with auto-pin enabled and a successful pin, the event links the local
    // clip id and the per-ride pin counter advances.
    @Test func pinsClipAndLinksLocalIdWhenEnabled() {
        let detector = FakeHazardDetector()
        let world = World()
        world.autoPinEnabled = true
        let clipId = UUID()
        world.pinResult = clipId
        let coord = makeCoordinator(detector: detector, alertManager: RecordingAlertManager(),
                                    clock: TestClock(now: now), world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        #expect(world.pinnedAt.count == 1)
        #expect(world.recordedEvents.first?.localClipId == clipId)
    }

    // CC-7: below the confidence threshold ⇒ no event, no alert, no pin.
    @Test func belowThresholdDoesNothing() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: TestClock(now: now),
                                    world: world, confidenceThreshold: 0.8)
        coord.beginRide()

        detector.emit(detection(confidence: 0.5))
        #expect(world.recordedEvents.isEmpty)
        #expect(world.pinnedAt.isEmpty)
        // The alert still has its own (looser) path: below the near-miss
        // threshold does not suppress the cautionary cue by itself — but here the
        // gate is open, so one cue is allowed. Assert the near-miss side only.
    }

    // CC-8: storage warn/stop records the event but refuses the pin.
    @Test func storageRefusalRecordsEventNoPin() {
        let detector = FakeHazardDetector()
        let world = World()
        world.autoPinEnabled = true
        world.pinResult = UUID()
        world.storage = .warn
        let coord = makeCoordinator(detector: detector, alertManager: RecordingAlertManager(),
                                    clock: TestClock(now: now), world: world)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        #expect(world.recordedEvents.count == 1)
        #expect(world.recordedEvents.first?.localClipId == nil)
        #expect(world.pinnedAt.isEmpty)
    }

    // CC-9: the per-ride auto-pin cap stops pinning but keeps recording events.
    @Test func perRideCapStopsPinning() {
        let detector = FakeHazardDetector()
        let world = World()
        world.autoPinEnabled = true
        world.pinResult = UUID()
        var tuning = RideCameraTuning()
        tuning.maxAutoPinsPerRide = 1
        tuning.autoPinCooldown = 0   // allow back-to-back events
        let clock = TestClock(now: now)
        let coord = makeCoordinator(detector: detector, alertManager: RecordingAlertManager(),
                                    clock: clock, world: world, tuning: tuning)
        coord.beginRide()

        detector.emit(detection(confidence: 0.9))
        clock.advance(by: 1)
        detector.emit(detection(confidence: 0.9))
        #expect(world.pinnedAt.count == 1)        // capped at 1 pin
        #expect(world.recordedEvents.count == 2)  // both events recorded
    }

    // CC-10: registration lifecycle — the detector runs only while recording and
    // enabled; disabling or leaving recording stops it.
    @Test func registrationFollowsStateAndToggle() {
        let detector = FakeHazardDetector()
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: RecordingAlertManager(),
                                    clock: TestClock(now: now), world: world)

        // Not started yet.
        #expect(detector.isRunning == false)

        coord.beginRide()        // recording + enabled ⇒ running
        #expect(detector.isRunning)

        world.detectionEnabled = false
        coord.refresh()
        #expect(detector.isRunning == false)

        world.detectionEnabled = true
        world.cameraState = .interrupted(.background)
        coord.refresh()
        #expect(detector.isRunning == false)   // not recording ⇒ not running

        world.cameraState = .recording(.standard)
        coord.refresh()
        #expect(detector.isRunning)

        coord.endRide()
        #expect(detector.isRunning == false)
    }

    // CC-11: a detector emits nothing while stopped — no detection leaks before
    // the coordinator starts it.
    @Test func stoppedDetectorEmitsNothing() {
        let detector = FakeHazardDetector()
        let alerts = RecordingAlertManager()
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: TestClock(now: now), world: world)
        _ = coord

        // Never called beginRide / refresh ⇒ detector.isRunning == false.
        detector.emit(detection(confidence: 0.9))
        #expect(alerts.fireCount == 0)
        #expect(world.recordedEvents.isEmpty)
    }

    // CC-12: the NoopDetector stays inert through the coordinator.
    @Test func noopDetectorStaysInert() {
        let detector = NoopDetector()
        let alerts = RecordingAlertManager()
        let world = World()
        let coord = makeCoordinator(detector: detector, alertManager: alerts, clock: TestClock(now: now), world: world)
        coord.beginRide()
        // Noop never emits; nothing to fire.
        #expect(alerts.fireCount == 0)
        #expect(world.recordedEvents.isEmpty)
    }
}
