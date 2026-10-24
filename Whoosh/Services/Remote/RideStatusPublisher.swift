import Foundation

/// Publishes `RideStatus` snapshots to an eyes-free surface through a
/// `RideRemoteControlling`, throttled by the pure `StatusThrottle` (rear-camera
/// spec task 13, Requirement 13.1; design "Eyes-free surfaces":
/// `RideStatusPublisher` throttles "on change, plus a 5 s heartbeat").
///
/// This task delivers the publish/throttle mechanism; it takes an already-built
/// `RideStatus` (the full builder that reads the camera coordinator, battery,
/// and crash coordinator is wired in a later task). The surface ticks the ride
/// clock itself from `RideStatus.anchorDate`, so a per-second message is
/// unnecessary — the throttle only forwards a changed status or a heartbeat.
///
/// `@MainActor` (project default isolation); the remote and clock run on the
/// main actor.
@MainActor
final class RideStatusPublisher {
    private let remote: RideRemoteControlling
    private let clock: Clock
    private let throttle: StatusThrottle

    private var lastPublished: RideStatus?
    private var lastPublishedAt: Date?

    init(
        remote: RideRemoteControlling,
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning()
    ) {
        self.remote = remote
        self.clock = clock
        self.throttle = StatusThrottle(heartbeat: tuning.statusHeartbeat)
    }

    /// Offer a status to the surface. It is forwarded only if the throttle says
    /// so (changed, or the heartbeat elapsed); otherwise it is dropped.
    func publish(_ status: RideStatus) {
        let now = clock.now()
        guard throttle.shouldPublish(
            status,
            last: lastPublished,
            lastPublishedAt: lastPublishedAt,
            now: now
        ) else { return }
        remote.publish(status)
        lastPublished = status
        lastPublishedAt = now
    }
}
