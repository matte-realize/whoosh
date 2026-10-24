import Foundation
import Testing
@testable import Whoosh

/// Tests for `FanOutAlertManager` (rear-camera task 13, Requirement 13.3–13.5;
/// design "Eyes-free surfaces"). Written test-first.
///
/// The fan-out is the `AlertManager` the rest of the app already calls. It owns
/// one `AlertSink` per channel and, on `fire(_:)`, asks the pure
/// `AlertRoutingPolicy` which channels to deliver on (given availability and
/// app state) and delivers to the matching sinks, in order. A sink that is
/// unavailable or throws must not stop the others, and the fan-out must never
/// block recording.
@MainActor
struct FanOutAlertManagerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func make(
        sinks: [FakeAlertSink],
        appState: AppAlertState = .foregroundRideMode
    ) -> (FanOutAlertManager, TestClock) {
        let clock = TestClock(now: now)
        let manager = FanOutAlertManager(
            sinks: sinks,
            clock: clock,
            appState: { appState }
        )
        return (manager, clock)
    }

    // Routes a rear-vehicle caution to the watch sink (first available channel),
    // not the others.
    @Test func routesRearVehicleToWatch() {
        let watch = FakeAlertSink(channel: .watchHaptic)
        let speaker = FakeAlertSink(channel: .phoneSpeaker)
        let (manager, _) = make(sinks: [watch, speaker])
        manager.fire(.cautionRearVehicle)
        #expect(watch.delivered.map(\.kind) == [.cautionRearVehicle])
        #expect(speaker.delivered.isEmpty)
    }

    // An important camera-stopped notice fans out to every available channel.
    @Test func fansOutCameraStopped() {
        let watch = FakeAlertSink(channel: .watchHaptic)
        let headphones = FakeAlertSink(channel: .phoneHeadphones)
        let (manager, _) = make(sinks: [watch, headphones])
        manager.fire(.cameraStopped(.thermal))
        #expect(watch.delivered.count == 1)
        #expect(headphones.delivered.count == 1)
    }

    // An unavailable sink is skipped; the available ones still receive the alert.
    @Test func skipsUnavailableSink() {
        let watch = FakeAlertSink(channel: .watchHaptic, isAvailable: false)
        let headphones = FakeAlertSink(channel: .phoneHeadphones)
        let (manager, _) = make(sinks: [watch, headphones])
        manager.fire(.cameraStopped(.storage))
        #expect(watch.delivered.isEmpty)
        #expect(headphones.delivered.count == 1)
    }

    // A throwing sink does not stop delivery to the others (non-blocking,
    // isolated failures — a failing sink never affects recording or the rest).
    @Test func throwingSinkDoesNotStopOthers() {
        let watch = FakeAlertSink(channel: .watchHaptic)
        watch.shouldThrow = true
        let headphones = FakeAlertSink(channel: .phoneHeadphones)
        let (manager, _) = make(sinks: [watch, headphones])
        manager.fire(.cameraStopped(.failed))
        #expect(headphones.delivered.count == 1)
    }

    // Per-kind cooldown: a second rear-vehicle caution within the cooldown is
    // dropped; after the cooldown it is delivered again.
    @Test func appliesCooldown() {
        let watch = FakeAlertSink(channel: .watchHaptic)
        let (manager, clock) = make(sinks: [watch])
        manager.fire(.cautionRearVehicle)
        #expect(watch.delivered.count == 1)
        clock.advance(by: 1)   // within 3 s cooldown
        manager.fire(.cautionRearVehicle)
        #expect(watch.delivered.count == 1)
        clock.advance(by: RideCameraTuning().rearVehicleAlertCooldown)
        manager.fire(.cautionRearVehicle)
        #expect(watch.delivered.count == 2)
    }

    // When locked/backgrounded a camera notice uses the local-notification sink.
    @Test func usesLocalNotificationWhenLocked() {
        let notif = FakeAlertSink(channel: .localNotification)
        let (manager, _) = make(sinks: [notif], appState: .lockedOrBackgrounded)
        manager.fire(.cameraInterrupted)
        #expect(notif.delivered.count == 1)
    }

    // A rear-vehicle caution is dropped when locked with no watch.
    @Test func dropsRearVehicleWhenLocked() {
        let notif = FakeAlertSink(channel: .localNotification)
        let (manager, _) = make(sinks: [notif], appState: .lockedOrBackgrounded)
        manager.fire(.cautionRearVehicle)
        #expect(notif.delivered.isEmpty)
    }

    // The fan-out conforms to the unchanged `AlertManager` protocol.
    @Test func isAnAlertManager() {
        let (manager, _) = make(sinks: [])
        let asProtocol: AlertManager = manager
        asProtocol.fire(.clipSaved)   // no sinks: no crash, no delivery
    }
}
