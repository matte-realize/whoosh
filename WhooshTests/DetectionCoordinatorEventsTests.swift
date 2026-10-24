import Foundation
import Testing
@testable import Whoosh

/// Tests for the detection-event observation seam added to `DetectionCoordinator`
/// so the parallel `NearMissRecorder` branch can subscribe without the
/// coordinator depending on it (ride-detection wiring). Driven with
/// `FakeHazardDetector` on the main actor; no camera, model, or frames.
@MainActor
struct DetectionCoordinatorEventsTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func makeCoordinator(
        detector: HazardDetector
    ) -> DetectionCoordinator {
        DetectionCoordinator(
            detector: detector,
            pipeline: nil,
            alertManager: RecordingAlertManager(),
            clock: TestClock(now: now),
            confidenceThreshold: 0.5,
            rideStateProvider: { .recording },
            currentSpeedProvider: { 5 },
            cameraStateProvider: { .recording(.standard) },
            isDetectionEnabled: { true },
            currentRideId: { UUID() }
        )
    }

    private func detection(_ confidence: Double) -> HazardDetection {
        HazardDetection(timestamp: now, kind: "vehicle", confidence: confidence, relativePositionHint: "center")
    }

    // The onDetection hook fires for every handled detection, carrying the raw
    // event (so a near-miss logger sees it even below the near-miss threshold).
    @Test func onDetectionHookFiresForEveryDetection() {
        let detector = FakeHazardDetector()
        let coord = makeCoordinator(detector: detector)
        var observed: [HazardDetection] = []
        coord.onDetection = { observed.append($0) }
        coord.beginRide()

        detector.emit(detection(0.9))
        detector.emit(detection(0.2)) // below near-miss threshold, still observed

        #expect(observed.count == 2)
        #expect(observed.map(\.confidence) == [0.9, 0.2])
    }

    // The detectionEvents() AsyncStream yields the same detections, so a caller
    // that prefers `for await` receives them.
    @Test func detectionEventsStreamYieldsDetections() async {
        let detector = FakeHazardDetector()
        let coord = makeCoordinator(detector: detector)
        let stream = coord.detectionEvents()
        coord.beginRide()

        detector.emit(detection(0.9))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.confidence == 0.9)
        #expect(first?.kind == "vehicle")
    }
}
