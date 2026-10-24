import Foundation
import Testing
@testable import Whoosh

/// Tests for `RideModeController` (rear-camera spec task 21), the `@Observable`
/// main-actor controller that drives the pure `ScreenModeStateMachine` +
/// `BrightnessGuard` and executes the effects-as-data against a
/// `FakeScreenController`, an `InMemoryDimGuardStore`, and a `TestClock`.
///
/// Each test maps to a row of the design's 15-row screen-mode table and/or a
/// `BrightnessGuard` case (BG-1…6). The controller owns the timers (grace and
/// the unlock-inactivity window), so time only moves when a test advances the
/// clock.
@MainActor
struct RideModeControllerTests {
    // MARK: Fixtures

    private func make(
        brightness: Double = 0.8,
        rideActive: Bool = true,
        rideModeEnabled: Bool = true,
        guardState: BrightnessGuardState? = nil,
        tuning: RideCameraTuning = RideCameraTuning()
    ) -> (RideModeController, FakeScreenController, InMemoryDimGuardStore, TestClock) {
        let screen = FakeScreenController(brightness: brightness)
        let store = InMemoryDimGuardStore(guardState: guardState)
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let controller = RideModeController(
            screen: screen,
            dimGuardStore: store,
            clock: clock,
            tuning: tuning,
            isRideActive: { rideActive },
            isRideModeEnabled: { rideModeEnabled }
        )
        return (controller, screen, store, clock)
    }

    // MARK: Row 1 — ride started ⇒ grace countdown

    @Test func rideStartedEntersGraceAndKeepsScreenAwake() {
        let (controller, screen, _, _) = make()

        controller.rideStarted()

        if case .graceCountdown = controller.mode {} else {
            Issue.record("expected graceCountdown, got \(controller.mode)")
        }
        #expect(screen.idleTimerDisabled == true)
        // Grace never dims yet.
        #expect(screen.setBrightnessHistory.isEmpty)
    }

    @Test func rideStartedIsANoOpWhenRideModeDisabled() {
        let (controller, screen, _, _) = make(rideModeEnabled: false)

        controller.rideStarted()

        #expect(controller.mode == .normal)
        #expect(screen.setIdleTimerCount == 0)
    }

    // MARK: Row 2 — grace elapses (timer) or "Dim now" ⇒ dimLocked

    @Test func graceTimerElapsingDimsAndLocksAndPersistsGuard() {
        let (controller, screen, store, clock) = make(brightness: 0.8)

        controller.rideStarted()
        // Grace is 20 s by default; advancing fires the scheduled graceElapsed.
        clock.advance(by: 20)

        #expect(controller.mode == .dimLocked)
        #expect(controller.isTouchLocked)
        #expect(screen.brightness == 0.0) // dimBrightness
        #expect(screen.setBrightnessHistory.last == 0.0)
        // The guard persisted the rider's original brightness (BG-1 / row 2).
        #expect(store.guardState?.original == 0.8)
        #expect(store.guardState?.dimmed == 0.0)
    }

    @Test func dimNowDimsImmediatelyBeforeGraceElapses() {
        let (controller, screen, store, _) = make(brightness: 0.6)

        controller.rideStarted()
        controller.dimNow()

        #expect(controller.mode == .dimLocked)
        #expect(screen.brightness == 0.0)
        #expect(store.guardState?.original == 0.6)
    }

    // MARK: Row 3 — "Keep screen on"

    @Test func keepScreenOnLeavesRideModeOffButKeepsAwake() {
        let (controller, screen, store, _) = make()

        controller.rideStarted()
        controller.keepScreenOn()

        #expect(controller.mode == .normal)
        #expect(screen.idleTimerDisabled == true)
        #expect(store.guardState == nil) // never dimmed, no guard
        #expect(!controller.isTouchLocked)
    }

    // MARK: Rows 4/5 — unlock restores brightness and shows controls

    @Test func twoFingerUnlockRestoresBrightnessAndShowsControls() {
        let (controller, screen, _, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.twoFingerHoldCompleted()

        if case .unlockedTemporarily = controller.mode {} else {
            Issue.record("expected unlockedTemporarily, got \(controller.mode)")
        }
        #expect(!controller.isTouchLocked)
        #expect(controller.isShowingControls)
        // Restored to the rider's original (BG-1).
        #expect(screen.brightness == 0.8)
    }

    @Test func accessibilityUnlockRestoresBrightness() {
        let (controller, screen, _, _) = make(brightness: 0.7)

        controller.rideStarted()
        controller.dimNow()
        controller.accessibilityUnlock()

        if case .unlockedTemporarily = controller.mode {} else {
            Issue.record("expected unlockedTemporarily, got \(controller.mode)")
        }
        #expect(screen.brightness == 0.7)
    }

    // MARK: Rows 6/7 — inactivity window extends then re-dims

    @Test func unlockWindowReDimsAfterInactivity() {
        let (controller, screen, _, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.twoFingerHoldCompleted() // unlockedTemporarily, 10 s window

        // Advance past the 10 s inactivity window ⇒ re-dim and re-lock.
        clock.advance(by: 10)

        #expect(controller.mode == .dimLocked)
        #expect(controller.isTouchLocked)
        #expect(screen.brightness == 0.0)
    }

    @Test func touchActivityExtendsTheUnlockWindow() {
        let (controller, _, _, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.twoFingerHoldCompleted()

        clock.advance(by: 6)
        controller.touchActivity() // reset the 10 s window at t+6
        clock.advance(by: 6)       // t+12 total, but only 6 s since the activity

        // Still unlocked (the window was extended).
        if case .unlockedTemporarily = controller.mode {} else {
            Issue.record("expected still unlockedTemporarily, got \(controller.mode)")
        }

        clock.advance(by: 4) // now 10 s since the last activity
        #expect(controller.mode == .dimLocked)
    }

    // MARK: Row 8 — resign active restores and clears the guard

    @Test func resignActiveRestoresBrightnessAndClearsGuard() {
        let (controller, screen, store, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        #expect(store.guardState != nil)

        controller.appResignedActive()

        #expect(controller.mode == .suspended)
        #expect(screen.brightness == 0.8)
        #expect(store.guardState == nil)
    }

    // MARK: Row 9 — becoming active again shows controls then re-dims

    @Test func becomingActiveAfterSuspendShowsControlsThenReDims() {
        let (controller, screen, _, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.appResignedActive()

        controller.appBecameActive()
        if case .unlockedTemporarily = controller.mode {} else {
            Issue.record("expected unlockedTemporarily, got \(controller.mode)")
        }
        #expect(screen.idleTimerDisabled == true)

        clock.advance(by: 10)
        #expect(controller.mode == .dimLocked)
    }

    // MARK: Row 10/11 — crash countdown forces full brightness + unlock

    @Test func crashCountdownForcesFullBrightnessAndSuppressesReDim() {
        let (controller, screen, _, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow() // dimLocked at 0.0

        controller.crashCountdownStarted()

        #expect(controller.mode == .normal)
        #expect(screen.brightness == 1.0)
        #expect(!controller.isTouchLocked)

        // Re-dim is suppressed: advancing does nothing while the countdown runs.
        clock.advance(by: 30)
        #expect(controller.mode == .normal)
        #expect(screen.brightness == 1.0)
    }

    @Test func crashCountdownEndedReturnsToUnlockThenReDims() {
        let (controller, _, _, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.crashCountdownStarted()
        controller.crashCountdownEnded()

        if case .unlockedTemporarily = controller.mode {} else {
            Issue.record("expected unlockedTemporarily, got \(controller.mode)")
        }

        clock.advance(by: 10)
        #expect(controller.mode == .dimLocked)
    }

    // MARK: Row 12 — ride ended restores and clears

    @Test func rideEndedRestoresBrightnessClearsGuardAndReleasesIdleTimer() {
        let (controller, screen, store, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()

        controller.rideEnded()

        #expect(controller.mode == .normal)
        #expect(screen.brightness == 0.8)
        #expect(store.guardState == nil)
        #expect(screen.idleTimerDisabled == false)
    }

    // MARK: Row 13 / BG-6 — external brightness change re-applies the minimum

    @Test func autoBrightnessWhileLockedIsReappliedToTheDimValue() {
        let (controller, screen, _, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow() // dimLocked at 0.0
        let countAfterDim = screen.setBrightnessHistory.count

        // The system raises brightness (Auto-Brightness) while locked.
        screen.simulateSystemBrightnessChange(0.5)

        #expect(controller.mode == .dimLocked)
        // The controller re-applied the dim value.
        #expect(screen.brightness == 0.0)
        #expect(screen.setBrightnessHistory.count > countAfterDim)
    }

    @Test func riderBrightnessChangeWhileUnlockedIsLeftAlone() {
        let (controller, screen, _, _) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow()
        controller.twoFingerHoldCompleted() // unlockedTemporarily, restored to 0.8
        let countAfterUnlock = screen.setBrightnessHistory.count

        // The rider slides brightness while unlocked ⇒ leave it (BG-2).
        screen.simulateSystemBrightnessChange(0.3)

        #expect(screen.brightness == 0.3)
        // No new controller write.
        #expect(screen.setBrightnessHistory.count == countAfterUnlock)
    }

    // MARK: Row 14 / BG-4 — launch with a persisted guard restores once

    @Test func reconcileOnLaunchRestoresPersistedOriginalAndClearsGuard() {
        // A previous run died while dimmed: original 0.9, screen now reads 0.0.
        let persisted = BrightnessGuardState(original: 0.9, dimmed: 0.0)
        let (controller, screen, store, _) = make(
            brightness: 0.0,
            rideActive: false,
            guardState: persisted
        )

        controller.reconcileOnLaunch()

        #expect(controller.mode == .normal)
        #expect(screen.brightness == 0.9)
        #expect(store.guardState == nil)
    }

    @Test func reconcileOnLaunchWithNoGuardDoesNothing() {
        let (controller, screen, store, _) = make(brightness: 0.5, rideActive: false)

        controller.reconcileOnLaunch()

        #expect(controller.mode == .normal)
        #expect(screen.setBrightnessHistory.isEmpty)
        #expect(store.guardState == nil)
    }

    // MARK: BG-5 — repeated enter without exit keeps the original

    @Test func reDimReappliesWithoutOverwritingTheStoredOriginal() {
        let (controller, screen, store, clock) = make(brightness: 0.8)

        controller.rideStarted()
        controller.dimNow() // original 0.8 stored
        controller.twoFingerHoldCompleted() // restored to 0.8
        clock.advance(by: 10) // re-dim (row 7)

        #expect(controller.mode == .dimLocked)
        #expect(screen.brightness == 0.0)
        // The stored original is still the rider's real brightness, not 0.0.
        #expect(store.guardState?.original == 0.8)
    }

    // MARK: Trouble indicator

    @Test func troubleFlagRaisesAndClears() {
        let (controller, _, _, _) = make()

        controller.rideStarted()
        controller.dimNow()
        #expect(!controller.isTrouble)

        controller.setTrouble(true)
        #expect(controller.isTrouble)

        controller.setTrouble(false)
        #expect(!controller.isTrouble)
    }
}
