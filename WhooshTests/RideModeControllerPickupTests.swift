import Foundation
import Testing
@testable import Whoosh

/// Tests for the ride-mode pickup response (owner device-testing feedback:
/// "when it dims there is no way to pick up the phone and stop it"). While the
/// screen is dimmed and locked, a pickup detected through the borrowed mount
/// sensor temporarily raises brightness and shows the unlock prompt, then
/// auto-reverts (re-dims) if the rider does not unlock. The rider can always
/// then hold to unlock and reach the big Stop control.
@MainActor
struct RideModeControllerPickupTests {
    private func make(
        brightness: Double = 0.8
    ) -> (RideModeController, FakeScreenController, FakeMountLevelSensor, TestClock) {
        let screen = FakeScreenController(brightness: brightness)
        let store = InMemoryDimGuardStore()
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let sensor = FakeMountLevelSensor()
        let controller = RideModeController(
            screen: screen,
            dimGuardStore: store,
            clock: clock,
            pickupSensor: sensor,
            isRideActive: { true },
            isRideModeEnabled: { true }
        )
        return (controller, screen, sensor, clock)
    }

    /// A large gravity change while dimmed raises brightness and sets the prompt.
    @Test func pickupWhileDimmedRaisesBrightnessAndPrompts() {
        let (controller, screen, sensor, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow() // dimLocked at 0.0; sensor starts
        #expect(sensor.isSensing)
        #expect(!controller.isPickupPrompting)

        // Seed the reference, then a 90° lift.
        sensor.emit(GravityVector(x: 0, y: -1, z: 0))
        sensor.emit(GravityVector(x: 0, y: 0, z: -1))

        #expect(controller.isPickupPrompting)
        #expect(screen.brightness > 0.0) // raised to a readable level
    }

    /// If the rider does not unlock, the prompt reverts and the screen re-dims.
    @Test func pickupPromptRevertsAfterWindow() {
        let (controller, screen, sensor, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        sensor.emit(GravityVector(x: 0, y: -1, z: 0))
        sensor.emit(GravityVector(x: 0, y: 0, z: -1))
        #expect(controller.isPickupPrompting)

        // Advance past the prompt window ⇒ revert + re-dim.
        clock.advance(by: 6)

        #expect(!controller.isPickupPrompting)
        #expect(controller.mode == .dimLocked)
        #expect(screen.brightness == 0.0)
    }

    /// The sensor only runs while dimmed: unlocking stops it and clears the
    /// prompt, so motion while unlocked never re-raises brightness behind the
    /// controls.
    @Test func unlockStopsSensorAndClearsPrompt() {
        let (controller, _, sensor, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        #expect(sensor.isSensing)

        controller.twoFingerHoldCompleted() // unlockedTemporarily

        #expect(!sensor.isSensing)
        #expect(!controller.isPickupPrompting)
    }

    /// Grace (not yet dimmed) does not run the sensor — a pickup there is the
    /// rider mounting the phone, not stopping the ride.
    @Test func sensorDoesNotRunDuringGrace() {
        let (controller, _, sensor, _) = make()

        controller.rideStarted() // graceCountdown

        #expect(!sensor.isSensing)
    }

    /// Ride end stops the sensor (no Core Motion left running).
    @Test func rideEndStopsSensor() {
        let (controller, _, sensor, _) = make()

        controller.rideStarted()
        controller.dimNow()
        #expect(sensor.isSensing)

        controller.rideEnded()

        #expect(!sensor.isSensing)
    }
}
