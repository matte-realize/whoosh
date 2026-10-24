import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `StatusThrottle` (rear-camera task 10, Requirement 13.1,
/// design "Eyes-free surfaces": `RideStatusPublisher` throttles with
/// `StatusThrottle` — on change, plus a heartbeat). Written test-first.
///
/// The throttle decides whether a new `RideStatus` should be published to the
/// eyes-free surface given the last published status and the last publish time:
/// publish when the status changed, or when the heartbeat interval has elapsed
/// since the last publish (so the watch knows the link is alive even when
/// nothing changed). The clock is injected as `now`.
struct StatusThrottleTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func status(distance: Double = 100, banner: String? = nil) -> RideStatus {
        RideStatus(
            rideState: .recording,
            activeDurationAnchor: 60,
            anchorDate: now,
            distanceMeters: distance,
            speedMetersPerSecond: 5,
            cameraState: .off,
            cameraStopReason: nil,
            storageStatus: .ok,
            thermalLevel: .nominal,
            phoneBatteryPercent: 0.8,
            isCharging: false,
            banner: banner,
            crashCountdownDeadline: nil,
            lastClipSavedAt: nil,
            lastDegradationNote: nil
        )
    }

    // First status is always published (no prior).
    @Test func firstStatusAlwaysPublishes() {
        let throttle = StatusThrottle(heartbeat: 5)
        #expect(throttle.shouldPublish(status(), last: nil, lastPublishedAt: nil, now: now))
    }

    // A changed status publishes even within the heartbeat window.
    @Test func changedStatusPublishes() {
        let throttle = StatusThrottle(heartbeat: 5)
        let prev = status(distance: 100)
        let next = status(distance: 200)
        #expect(throttle.shouldPublish(next, last: prev, lastPublishedAt: now, now: now.addingTimeInterval(1)))
    }

    // An unchanged status within the heartbeat window does NOT publish.
    @Test func unchangedWithinHeartbeatDoesNotPublish() {
        let throttle = StatusThrottle(heartbeat: 5)
        let s = status()
        #expect(!throttle.shouldPublish(s, last: s, lastPublishedAt: now, now: now.addingTimeInterval(4)))
    }

    // An unchanged status at/after the heartbeat interval publishes (keep-alive).
    @Test func unchangedAtHeartbeatPublishes() {
        let throttle = StatusThrottle(heartbeat: 5)
        let s = status()
        #expect(throttle.shouldPublish(s, last: s, lastPublishedAt: now, now: now.addingTimeInterval(5)))
    }

    // A banner change (not just numbers) is a change that publishes.
    @Test func bannerChangePublishes() {
        let throttle = StatusThrottle(heartbeat: 5)
        let prev = status(banner: nil)
        let next = status(banner: "Camera paused")
        #expect(throttle.shouldPublish(next, last: prev, lastPublishedAt: now, now: now.addingTimeInterval(1)))
    }

    // Default heartbeat is the design's 5 s.
    @Test func defaultHeartbeatIsFiveSeconds() {
        let throttle = StatusThrottle()
        #expect(throttle.heartbeat == 5)
    }
}
