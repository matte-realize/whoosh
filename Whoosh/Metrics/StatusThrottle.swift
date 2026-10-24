import Foundation

/// Pure throttle deciding when a `RideStatus` should be published to an
/// eyes-free surface (rear-camera spec task 10, Requirement 13.1; design
/// "Eyes-free surfaces": `RideStatusPublisher` throttles "on change, plus a 5 s
/// heartbeat").
///
/// Publishing on every status rebuild would flood the WatchConnectivity link;
/// never publishing would leave the watch unsure the link is alive. So the
/// throttle publishes when the status changed, or when the heartbeat interval
/// has elapsed since the last publish. The surface ticks the ride clock itself
/// from `RideStatus.anchorDate`, so a per-second message is unnecessary.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). `now` is
/// passed in; there is no clock object to keep this value-type testable.
struct StatusThrottle: Equatable, Sendable {
    /// Maximum time between publishes even when nothing changed (keep-alive).
    let heartbeat: TimeInterval

    init(heartbeat: TimeInterval = 5) {
        self.heartbeat = heartbeat
    }

    /// Whether `candidate` should be published given the last published status
    /// and when it was published.
    ///
    /// - A first status (`last == nil` or `lastPublishedAt == nil`) always
    ///   publishes.
    /// - A status that differs from `last` publishes immediately.
    /// - An unchanged status publishes only once `heartbeat` has elapsed since
    ///   `lastPublishedAt` (boundary inclusive).
    func shouldPublish(
        _ candidate: RideStatus,
        last: RideStatus?,
        lastPublishedAt: Date?,
        now: Date
    ) -> Bool {
        guard let last, let lastPublishedAt else { return true }
        if candidate != last { return true }
        return now.timeIntervalSince(lastPublishedAt) >= heartbeat
    }
}
