import Foundation
import Testing
@testable import Whoosh

/// Tests for `RideDetectionCoordinator` — the composition that actually runs
/// rear-vehicle detection during a ride (ride-detection wiring). It verifies the
/// missing wire end-to-end with fakes and a **real** `FramePipeline`: the vision
/// consumer is registered on the pipeline while recording and removed on
/// pause/interruption/stop/ride-end, and the chip state reflects the model's
/// load outcome. No CoreML model is loaded (the loader is faked), so these run
/// on the simulator without a camera.
@MainActor
struct RideDetectionCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    /// Build a coordinator over a real pipeline and a `VisionVehicleConsumer`
    /// whose model loader is faked (throws by default so no real model is
    /// needed). Returns the coordinator and the pipeline so tests can assert
    /// registration.
    private func make(
        enabled: Bool = true
    ) -> (RideDetectionCoordinator, FramePipeline) {
        let pipeline = FramePipeline()
        let consumer = VisionVehicleConsumer(
            loadDetector: {
                // Never load a real model in tests.
                throw DetectorLoadErrorStub.unavailable
            }
        )
        let clock = TestClock(now: now)
        let coord = RideDetectionCoordinator(
            consumer: consumer,
            isEnabled: { enabled },
            makeCoordinator: { detector, cameraStateProvider, isDetectionEnabled in
                DetectionCoordinator(
                    detector: detector,
                    pipeline: pipeline,
                    alertManager: RecordingAlertManager(),
                    clock: clock,
                    confidenceThreshold: 0.5,
                    rideStateProvider: { .recording },
                    currentSpeedProvider: { 5 },
                    cameraStateProvider: cameraStateProvider,
                    isDetectionEnabled: isDetectionEnabled,
                    currentRideId: { UUID() }
                )
            }
        )
        return (coord, pipeline)
    }

    private enum DetectorLoadErrorStub: Error { case unavailable }

    // The detector is registered on the shared pipeline when recording starts.
    @Test func registersConsumerWhenRecordingStarts() {
        let (coord, pipeline) = make()
        coord.beginRide()
        #expect(pipeline.consumerCount == 0) // beginRide alone does not record

        coord.cameraStateChanged(.recording(.standard))
        #expect(pipeline.consumerCount == 1)
    }

    // The detector is removed when recording stops (ride end), pauses
    // (interrupted), or the camera goes off.
    @Test func unregistersConsumerWhenRecordingStops() {
        let (coord, pipeline) = make()
        coord.beginRide()
        coord.cameraStateChanged(.recording(.standard))
        #expect(pipeline.consumerCount == 1)

        // Interruption (pause/lock/call) ⇒ not recording ⇒ removed.
        coord.cameraStateChanged(.interrupted(.background))
        #expect(pipeline.consumerCount == 0)

        // Resume ⇒ re-registered.
        coord.cameraStateChanged(.recording(.standard))
        #expect(pipeline.consumerCount == 1)

        // Ride end ⇒ removed.
        coord.endRide()
        #expect(pipeline.consumerCount == 0)
    }

    // A camera failure removes the detector (detection never keeps running once
    // capture has failed); recording/ride are unaffected (not asserted here).
    @Test func unregistersOnCameraFailure() {
        let (coord, pipeline) = make()
        coord.beginRide()
        coord.cameraStateChanged(.recording(.standard))
        #expect(pipeline.consumerCount == 1)

        coord.cameraStateChanged(.failed(.startTimeout))
        #expect(pipeline.consumerCount == 0)
    }

    // When rear detection is disabled, nothing registers and the chip is off.
    @Test func disabledNeverRegistersAndChipIsOff() {
        let (coord, pipeline) = make(enabled: false)
        coord.beginRide()
        coord.cameraStateChanged(.recording(.standard))
        #expect(pipeline.consumerCount == 0)
        #expect(coord.detectionState == .off)
    }

    // The chip shows "loading" while recording before the model resolves.
    @Test func chipLoadingWhileRecordingBeforeModelResolves() {
        let (coord, _) = make()
        coord.beginRide()
        coord.cameraStateChanged(.recording(.standard))
        // The async load has not reported back yet ⇒ loading.
        #expect(coord.detectionState == .loading)
    }

    // The chip shows "unavailable" once the model load fails. The load is async;
    // poll briefly for the main-actor callback.
    @Test func chipUnavailableWhenModelLoadFails() async {
        let (coord, _) = make()
        coord.beginRide()
        coord.cameraStateChanged(.recording(.standard))

        // Wait for the consumer's async load to fail and report back.
        var resolved = false
        for _ in 0..<200 {
            if coord.detectionState == .unavailable { resolved = true; break }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }
        #expect(resolved)
    }
}
