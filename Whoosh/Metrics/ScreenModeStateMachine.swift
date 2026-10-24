import Foundation

/// The pure ride-mode screen reducer: `(state, event, context) → (state,
/// [effects])` implementing every row of the design's 15-row transition table
/// (rear-camera spec Requirement 10.2, 10.3, 10.5, 10.7, 13.7, 19.2).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). It performs
/// no I/O, touches no `UIScreen`, and reads no clock; the current instant and
/// the ride/ride-mode flags come in via `ScreenModeContext`, and the deadlines
/// it produces are absolute `Date`s derived from `context.now`. Effects are
/// returned as **data** for the `RideModeController` (task 21) to execute
/// against the real `ScreenController`.
///
/// Invariants (design "Ride mode"):
/// - Undefined transitions are **no-ops** (row 15), never crashes.
/// - A crash countdown always forces full brightness and unlock (row 10),
///   whatever the current mode (Requirement 13.7).
/// - Every exit path (resign active, ride end, launch guard) restores the
///   rider's brightness and clears the persisted guard, so the phone is never
///   left dim (Requirement 10.2).
enum ScreenModeStateMachine {
    /// Reduce one event. Returns the next screen mode and ordered effects.
    static func reduce(
        _ state: ScreenMode,
        _ event: ScreenModeEvent,
        _ context: ScreenModeContext
    ) -> ScreenModeReduction {
        switch event {
        // Row 10: a crash countdown forces full brightness + unlock from ANY
        // mode, so it is handled before the per-state switch (Requirement 13.7).
        case .crashCountdownStarted:
            return ScreenModeReduction(
                state: .normal,
                effects: [.setBrightness(1.0), .setTouchLocked(false), .suppressRedim(true)]
            )

        // Row 12: the ride ended ⇒ restore and clear from any mode.
        case .rideEnded:
            return ScreenModeReduction(
                state: .normal,
                effects: [.restoreBrightness, .clearGuard, .setIdleTimerDisabled(false)]
            )

        // Row 8: the app resigned active ⇒ suspend and restore from any ride-mode
        // state (grace/dimLocked/unlockedTemporarily). Undefined elsewhere.
        case .appResignedActive:
            switch state {
            case .graceCountdown, .dimLocked, .unlockedTemporarily:
                return ScreenModeReduction(
                    state: .suspended,
                    effects: [.restoreBrightness, .clearGuard]
                )
            default:
                return noOp(state)
            }

        // Row 13: external brightness change ⇒ re-apply minimum while dimLocked;
        // leave it if the rider changed it deliberately while unlocked.
        case let .systemBrightnessChanged(_, riderInitiated):
            switch state {
            case .dimLocked where !riderInitiated:
                return ScreenModeReduction(
                    state: .dimLocked,
                    effects: [.setBrightness(context.tuning.dimBrightness)]
                )
            default:
                return noOp(state)
            }

        // Row 14: launched with a persisted dim guard and no active ride ⇒
        // restore the saved original once, clear the guard.
        case .launchWithActiveGuard:
            guard !context.rideActive else { return noOp(state) }
            return ScreenModeReduction(
                state: .normal,
                effects: [.restorePersistedOriginal, .clearGuard]
            )

        default:
            return reduceStateful(state, event, context)
        }
    }

    // MARK: - State-dependent transitions (rows 1–7, 9, 11)

    private static func reduceStateful(
        _ state: ScreenMode,
        _ event: ScreenModeEvent,
        _ context: ScreenModeContext
    ) -> ScreenModeReduction {
        switch (state, event) {
        // Row 1: ride started with ride mode + camera on ⇒ grace countdown.
        case (.normal, .rideStarted):
            guard context.rideModeEnabled else { return noOp(state) }
            let deadline = context.graceDeadline
            return ScreenModeReduction(
                state: .graceCountdown(until: deadline),
                effects: [.setIdleTimerDisabled(true), .showGraceCountdown(until: deadline)]
            )

        // Row 2: "Dim now" or the grace countdown elapsed ⇒ dim and lock.
        case (.graceCountdown, .dimNow), (.graceCountdown, .graceElapsed):
            return ScreenModeReduction(
                state: .dimLocked,
                effects: [
                    .storeOriginalBrightnessAndPersistGuard,
                    .setBrightness(context.tuning.dimBrightness),
                    .setTouchLocked(true),
                ]
            )

        // Row 3: "Keep screen on" ⇒ ride mode off for this ride; idle timer stays
        // off so the active-ride screen does not sleep.
        case (.graceCountdown, .keepScreenOn):
            return ScreenModeReduction(
                state: .normal,
                effects: [.setIdleTimerDisabled(true)]
            )

        // Rows 4, 5: unlock (gesture or accessibility action) ⇒ restore, show
        // controls, start the temporary-unlock window.
        case (.dimLocked, .twoFingerHoldCompleted), (.dimLocked, .accessibilityUnlock):
            return ScreenModeReduction(
                state: .unlockedTemporarily(until: context.unlockDeadline),
                effects: [.restoreBrightness, .setTouchLocked(false), .showControls]
            )

        // Row 6: touch activity while unlocked ⇒ extend the deadline only.
        case (.unlockedTemporarily, .touchActivity):
            return ScreenModeReduction(state: .unlockedTemporarily(until: context.unlockDeadline))

        // Row 7: the unlock window elapsed ⇒ re-dim and re-lock.
        case (.unlockedTemporarily, .unlockDeadlineReached):
            return ScreenModeReduction(
                state: .dimLocked,
                effects: [.setBrightness(context.tuning.dimBrightness), .setTouchLocked(true)]
            )

        // Row 9: the app became active again ⇒ show controls briefly, then re-dim
        // (the temporary-unlock window). Only while a ride is active and ride
        // mode is on; otherwise a no-op.
        case (.suspended, .appBecameActive):
            guard context.rideActive, context.rideModeEnabled else { return noOp(state) }
            return ScreenModeReduction(
                state: .unlockedTemporarily(until: context.unlockDeadline),
                effects: [.setIdleTimerDisabled(true)]
            )

        // Row 11: the crash countdown ended ⇒ return to the temporary-unlock
        // window (then re-dim) while a ride is active; stop suppressing re-dim.
        case (.normal, .crashCountdownEnded):
            guard context.rideActive else { return noOp(state) }
            return ScreenModeReduction(
                state: .unlockedTemporarily(until: context.unlockDeadline),
                effects: [.suppressRedim(false)]
            )

        // Row 15: anything else is undefined ⇒ no-op.
        default:
            return noOp(state)
        }
    }

    // MARK: - Helpers

    private static func noOp(_ state: ScreenMode) -> ScreenModeReduction {
        ScreenModeReduction(state: state)
    }
}
