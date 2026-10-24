import Foundation
import OSLog

/// Persists near-miss events produced by the `DetectionCoordinator` (rear-camera
/// spec task 28; Requirements 15.1–15.5). The coordinator does the pure
/// orchestration — decide via `NearMissPolicy`, look up the nearest accepted
/// route point, request a clip pin through its injected seam, and flag demo
/// events — then hands the finished `NearMissEvent` to this recorder's `record`
/// sink, which writes it to the `NearMissRepository` with the ride.
///
/// Keeping the recorder as the single persistence sink means:
/// - the coordinator stays pure and framework-free about storage,
/// - every event (detector or demo-mode "Simulate approaching vehicle") lands in
///   the same local store, tied to its ride,
/// - a storage failure is swallowed with a log and **never** affects ride
///   recording or the alert cue (safety features must not depend on storage).
///
/// Footage never leaves the device: an event may carry a local-only clip id, but
/// it is never uploaded (`NearMissUploadMapper` drops it). Demo events are stored
/// locally (so the demo shows markers) but excluded from upload by the sync path.
///
/// `@MainActor` to match the repository and the coordinator; persisting an event
/// is small metadata work.
@MainActor
final class NearMissRecorder {
    private let repository: NearMissRepository
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "NearMissRecorder"
    )

    init(repository: NearMissRepository) {
        self.repository = repository
    }

    /// Persist one finished event. Tolerant: a storage failure is logged and
    /// swallowed so it never interrupts the ride or the safety cue.
    func record(_ event: NearMissEvent) {
        do {
            try repository.save(event)
        } catch {
            Self.logger.error(
                "Failed to store near-miss \(event.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
