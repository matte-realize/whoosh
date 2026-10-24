import Foundation

/// A test/preview `HazardDetector` that emits `HazardDetection`s **on command**
/// instead of from a camera (rear-camera spec task 14). It lets the
/// `DetectionCoordinator`, alert routing, and the near-miss/clip seams be
/// exercised end-to-end with no camera, model, or frames — the real model run is
/// a device check.
///
/// It records `start()`/`stop()` so tests can assert the coordinator only runs a
/// detector while the camera is recording/degraded and detection is enabled. It
/// never owns capture or requests permission (the `HazardDetector` contract).
///
/// `onDetection` is delivered synchronously on the caller's actor: tests and the
/// coordinator drive it from the main actor, matching the real detector's
/// "deliver on the main actor" contract without needing a hop.
final class FakeHazardDetector: HazardDetector {
    var onDetection: ((HazardDetection) -> Void)?

    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init() {}

    func start() {
        isRunning = true
        startCount += 1
    }

    func stop() {
        isRunning = false
        stopCount += 1
    }

    /// Emit a detection as if the model produced one. A no-op while stopped, so a
    /// detector that the coordinator has not started cannot leak detections.
    func emit(_ detection: HazardDetection) {
        guard isRunning else { return }
        onDetection?(detection)
    }

    /// Convenience: emit a vehicle detection with the given fields.
    func emitVehicle(
        at timestamp: Date,
        confidence: Double,
        positionHint: String? = "center"
    ) {
        emit(
            HazardDetection(
                timestamp: timestamp,
                kind: "vehicle",
                confidence: confidence,
                relativePositionHint: positionHint
            )
        )
    }
}
