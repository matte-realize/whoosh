import Foundation
import Testing
@testable import Whoosh

/// Tests for `RideStatusPublisher` and the `RideRemoteControlling` fakes
/// (rear-camera task 13, Requirement 13.1; design "Eyes-free surfaces"). Written
/// test-first.
///
/// `RideStatusPublisher` builds a `RideStatus` and, using the pure
/// `StatusThrottle`, publishes it through a `RideRemoteControlling` only on
/// change or at the heartbeat. `NoopRideRemote` is inert; `FakeRideRemote`
/// records published statuses and can deliver scripted commands.
@MainActor
struct RideStatusPublisherTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func status(distance: Double) -> RideStatus {
        RideStatus(
            rideState: .recording,
            activeDurationAnchor: 10,
            anchorDate: now,
            distanceMeters: distance,
            speedMetersPerSecond: 4,
            cameraState: .off,
            cameraStopReason: nil,
            storageStatus: .ok,
            thermalLevel: .nominal,
            phoneBatteryPercent: 0.9,
            isCharging: false,
            banner: nil,
            crashCountdownDeadline: nil,
            lastClipSavedAt: nil,
            lastDegradationNote: nil
        )
    }

    // First status is published to the remote.
    @Test func publishesFirstStatus() {
        let remote = FakeRideRemote()
        let clock = TestClock(now: now)
        let publisher = RideStatusPublisher(remote: remote, clock: clock)
        publisher.publish(status(distance: 100))
        #expect(remote.published.count == 1)
        #expect(remote.published.last?.distanceMeters == 100)
    }

    // A changed status publishes; an unchanged one within the heartbeat does not.
    @Test func throttlesUnchangedWithinHeartbeat() {
        let remote = FakeRideRemote()
        let clock = TestClock(now: now)
        let publisher = RideStatusPublisher(remote: remote, clock: clock)
        publisher.publish(status(distance: 100))
        clock.advance(by: 1)
        publisher.publish(status(distance: 100))   // unchanged, within heartbeat
        #expect(remote.published.count == 1)

        publisher.publish(status(distance: 200))   // changed
        #expect(remote.published.count == 2)
    }

    // An unchanged status at the heartbeat boundary publishes (keep-alive).
    @Test func publishesHeartbeat() {
        let remote = FakeRideRemote()
        let clock = TestClock(now: now)
        let publisher = RideStatusPublisher(remote: remote, clock: clock)
        publisher.publish(status(distance: 100))
        clock.advance(by: 5)
        publisher.publish(status(distance: 100))
        #expect(remote.published.count == 2)
    }

    // NoopRideRemote accepts publishes and commands without doing anything.
    @Test func noopIsInert() {
        let remote = NoopRideRemote()
        remote.publish(status(distance: 1))        // no crash
        #expect(remote.isReachable == false)
        var invoked = false
        remote.onCommand = { _, reply in invoked = true; reply(.accepted) }
        // Noop never invokes onCommand (there is no surface).
        #expect(invoked == false)
    }

    // FakeRideRemote delivers a scripted command and captures its reply.
    @Test func fakeDeliversCommand() {
        let remote = FakeRideRemote()
        var received: RideRemoteCommand?
        remote.onCommand = { command, reply in
            received = command
            reply(.accepted)
        }
        let reply = remote.deliver(.saveClip)
        #expect(received == .saveClip)
        #expect(reply == .accepted)
    }

    // FakeRideRemote reports reachability it is scripted with.
    @Test func fakeReportsReachability() {
        let remote = FakeRideRemote(isReachable: false)
        #expect(remote.isReachable == false)
        remote.isReachable = true
        #expect(remote.isReachable)
    }
}
