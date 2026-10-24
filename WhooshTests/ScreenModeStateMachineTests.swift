import Foundation
import Testing
@testable import Whoosh

/// Row-by-row tests for the pure `ScreenModeStateMachine` reducer (rear-camera
/// task 8, Requirements 10.2, 10.3, 10.5, 10.7, 13.7, 19.2). One test per row of
/// the design's 15-row transition table (SM-1…15), using a `TestClock` as the
/// source of `now` so deadlines are deterministic and no real time passes.
struct ScreenModeStateMachineTests {
    private let tuning = RideCameraTuning()
    private let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))

    private var t0: Date { clock.now() }

    private func ctx(
        rideActive: Bool = true,
        rideModeEnabled: Bool = true
    ) -> ScreenModeContext {
        ScreenModeContext(
            now: clock.now(),
            tuning: tuning,
            rideActive: rideActive,
            rideModeEnabled: rideModeEnabled
        )
    }

    private func reduce(
        _ state: ScreenMode,
        _ event: ScreenModeEvent,
        _ context: ScreenModeContext
    ) -> ScreenModeReduction {
        ScreenModeStateMachine.reduce(state, event, context)
    }

    // MARK: SM-1 — normal + ride started (ride mode on) ⇒ graceCountdown

    @Test func sm1_rideStartedEntersGrace() {
        let r = reduce(.normal, .rideStarted, ctx())
        #expect(r.state == .graceCountdown(until: t0.addingTimeInterval(tuning.mountGrace)))
        #expect(r.effects.contains(.setIdleTimerDisabled(true)))
        #expect(r.effects.contains(.showGraceCountdown(until: t0.addingTimeInterval(tuning.mountGrace))))
    }

    /// Guard: ride mode off ⇒ ride started is a no-op (stays normal).
    @Test func sm1_rideStartedWithRideModeOffIsNoOp() {
        let r = reduce(.normal, .rideStarted, ctx(rideModeEnabled: false))
        #expect(r.state == .normal)
        #expect(r.effects.isEmpty)
    }

    // MARK: SM-2 — graceCountdown + "Dim now" / elapsed ⇒ dimLocked

    @Test func sm2_dimNowDimsAndLocks() {
        let r = reduce(.graceCountdown(until: t0), .dimNow, ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.contains(.storeOriginalBrightnessAndPersistGuard))
        #expect(r.effects.contains(.setBrightness(tuning.dimBrightness)))
        #expect(r.effects.contains(.setTouchLocked(true)))
    }

    @Test func sm2_graceElapsedDimsAndLocks() {
        let r = reduce(.graceCountdown(until: t0), .graceElapsed, ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.contains(.storeOriginalBrightnessAndPersistGuard))
        #expect(r.effects.contains(.setBrightness(tuning.dimBrightness)))
        #expect(r.effects.contains(.setTouchLocked(true)))
    }

    // MARK: SM-3 — graceCountdown + "Keep screen on" ⇒ normal (ride mode off)

    @Test func sm3_keepScreenOnStaysNormalIdleTimerOff() {
        let r = reduce(.graceCountdown(until: t0), .keepScreenOn, ctx())
        #expect(r.state == .normal)
        // Idle timer stays off even with ride mode declined for this ride.
        #expect(r.effects.contains(.setIdleTimerDisabled(true)))
        // No dimming happened, so nothing to restore.
        #expect(!r.effects.contains(.restoreBrightness))
    }

    // MARK: SM-4 — dimLocked + two-finger hold ⇒ unlockedTemporarily

    @Test func sm4_twoFingerHoldUnlocks() {
        let r = reduce(.dimLocked, .twoFingerHoldCompleted, ctx())
        #expect(r.state == .unlockedTemporarily(until: t0.addingTimeInterval(tuning.unlockInactivityWindow)))
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.setTouchLocked(false)))
        #expect(r.effects.contains(.showControls))
    }

    // MARK: SM-5 — dimLocked + accessibility unlock ⇒ unlockedTemporarily

    @Test func sm5_accessibilityUnlock() {
        let r = reduce(.dimLocked, .accessibilityUnlock, ctx())
        #expect(r.state == .unlockedTemporarily(until: t0.addingTimeInterval(tuning.unlockInactivityWindow)))
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.setTouchLocked(false)))
        #expect(r.effects.contains(.showControls))
    }

    // MARK: SM-6 — unlockedTemporarily + touch activity ⇒ extended deadline

    @Test func sm6_touchActivityExtendsWindow() {
        // Advance so the extended deadline differs from the original.
        let original = ScreenMode.unlockedTemporarily(until: t0)
        clock.advance(by: 3)
        let r = reduce(original, .touchActivity, ctx())
        #expect(r.state == .unlockedTemporarily(until: clock.now().addingTimeInterval(tuning.unlockInactivityWindow)))
        // Extending must not re-dim or lock.
        #expect(!r.effects.contains(.setBrightness(tuning.dimBrightness)))
        #expect(!r.effects.contains(.setTouchLocked(true)))
    }

    // MARK: SM-7 — unlockedTemporarily + deadline reached ⇒ dimLocked

    @Test func sm7_deadlineReachedRedims() {
        let r = reduce(.unlockedTemporarily(until: t0), .unlockDeadlineReached, ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.contains(.setBrightness(tuning.dimBrightness)))
        #expect(r.effects.contains(.setTouchLocked(true)))
    }

    // MARK: SM-8 — any ride-mode state + resign active ⇒ suspended

    @Test func sm8_resignActiveFromDimLockedSuspends() {
        let r = reduce(.dimLocked, .appResignedActive, ctx())
        #expect(r.state == .suspended)
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.clearGuard))
    }

    @Test func sm8_resignActiveFromUnlockedSuspends() {
        let r = reduce(.unlockedTemporarily(until: t0), .appResignedActive, ctx())
        #expect(r.state == .suspended)
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.clearGuard))
    }

    @Test func sm8_resignActiveFromGraceSuspends() {
        let r = reduce(.graceCountdown(until: t0), .appResignedActive, ctx())
        #expect(r.state == .suspended)
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.clearGuard))
    }

    // MARK: SM-9 — suspended + become active (ride active, ride mode on) ⇒ unlockedTemporarily

    @Test func sm9_becomeActiveResumesUnlocked() {
        let r = reduce(.suspended, .appBecameActive, ctx())
        #expect(r.state == .unlockedTemporarily(until: t0.addingTimeInterval(tuning.unlockInactivityWindow)))
        #expect(r.effects.contains(.setIdleTimerDisabled(true)))
    }

    /// Guard: not active / ride mode off ⇒ stay suspended (no-op).
    @Test func sm9_becomeActiveWithoutRideIsNoOp() {
        let r = reduce(.suspended, .appBecameActive, ctx(rideActive: false))
        #expect(r.state == .suspended)
        #expect(r.effects.isEmpty)
    }

    // MARK: SM-10 — any + crash countdown started ⇒ normal (forced), full brightness

    @Test func sm10_crashCountdownForcesFullBrightUnlock() {
        let r = reduce(.dimLocked, .crashCountdownStarted, ctx())
        #expect(r.state == .normal)
        #expect(r.effects.contains(.setBrightness(1.0)))
        #expect(r.effects.contains(.setTouchLocked(false)))
        #expect(r.effects.contains(.suppressRedim(true)))
    }

    // MARK: SM-11 — normal(forced) + crash countdown ended (ride active) ⇒ unlockedTemporarily

    @Test func sm11_crashCountdownEndedReturnsToUnlocked() {
        let r = reduce(.normal, .crashCountdownEnded, ctx())
        #expect(r.state == .unlockedTemporarily(until: t0.addingTimeInterval(tuning.unlockInactivityWindow)))
        #expect(r.effects.contains(.suppressRedim(false)))
    }

    /// Guard: ride not active ⇒ stay normal (no-op).
    @Test func sm11_crashCountdownEndedWithoutRideIsNoOp() {
        let r = reduce(.normal, .crashCountdownEnded, ctx(rideActive: false))
        #expect(r.state == .normal)
        #expect(r.effects.isEmpty)
    }

    // MARK: SM-12 — any + ride ended ⇒ normal, restore & clear guard

    @Test func sm12_rideEndedRestores() {
        let r = reduce(.dimLocked, .rideEnded, ctx())
        #expect(r.state == .normal)
        #expect(r.effects.contains(.restoreBrightness))
        #expect(r.effects.contains(.clearGuard))
    }

    // MARK: SM-13 — dimLocked + external brightness change ⇒ re-apply minimum

    @Test func sm13_externalBrightnessChangeReapplied() {
        let r = reduce(.dimLocked, .systemBrightnessChanged(value: 0.7, riderInitiated: false), ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.contains(.setBrightness(tuning.dimBrightness)))
    }

    /// Rider changed brightness deliberately while unlocked ⇒ leave it (no-op).
    @Test func sm13_riderBrightnessChangeWhileUnlockedLeftAlone() {
        let r = reduce(.unlockedTemporarily(until: t0), .systemBrightnessChanged(value: 0.7, riderInitiated: true), ctx())
        #expect(r.state == .unlockedTemporarily(until: t0))
        #expect(r.effects.isEmpty)
    }

    // MARK: SM-14 — launch with active guard, no ride ⇒ normal, restore persisted

    @Test func sm14_launchGuardRestores() {
        let r = reduce(.normal, .launchWithActiveGuard, ctx(rideActive: false))
        #expect(r.state == .normal)
        #expect(r.effects.contains(.restorePersistedOriginal))
        #expect(r.effects.contains(.clearGuard))
    }

    // MARK: SM-15 — undefined transition ⇒ no-op

    @Test func sm15_undefinedTransitionIsNoOp() {
        // "Dim now" only applies during the grace countdown; from dimLocked it is
        // undefined and must be a no-op.
        let r = reduce(.dimLocked, .dimNow, ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.isEmpty)
    }

    @Test func sm15_touchActivityWhenDimLockedIsNoOp() {
        let r = reduce(.dimLocked, .touchActivity, ctx())
        #expect(r.state == .dimLocked)
        #expect(r.effects.isEmpty)
    }
}
