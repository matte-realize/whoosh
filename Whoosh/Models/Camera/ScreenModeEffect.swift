import Foundation

/// Effects produced by the pure `ScreenModeStateMachine` reducer — **data, not
/// actions** (rear-camera spec design "ScreenModeStateMachine"; the same pattern
/// as `CrashEffect`). The reducer performs no I/O and touches no screen; the
/// `RideModeController` (`Services/Screen` + `Features/Camera`, task 21)
/// interprets these against the real `ScreenController`.
///
/// Foundation-only; `Equatable`, `Sendable`. Brightness values are 0...1
/// fractions; the actual minimum/dim target is the reducer's input
/// (`context.tuning.dimBrightness`), surfaced here as `setBrightness`.
enum ScreenModeEffect: Equatable, Sendable {
    /// Show the mount-grace countdown UI with its deadline (row 1).
    case showGraceCountdown(until: Date)
    /// Record the rider's current brightness as the original to restore later,
    /// and persist the dim guard so a crashed/killed run can restore on launch
    /// (row 2).
    case storeOriginalBrightnessAndPersistGuard
    /// Set the screen brightness to `value` (0...1). Dimming uses
    /// `context.tuning.dimBrightness`; restoring uses the stored original.
    case setBrightness(Double)
    /// Restore the rider's original brightness (rows 4, 5, 8, 12).
    case restoreBrightness
    /// Clear the persisted dim guard (rows 8, 12, 14).
    case clearGuard
    /// Enable (true) or disable (false) the idle timer. Ride mode disables it so
    /// the screen never sleeps (rows 1, 3, 9).
    case setIdleTimerDisabled(Bool)
    /// Turn the full-screen touch lock on (true) or off (false) (rows 2, 4).
    case setTouchLocked(Bool)
    /// Show the unlocked ride controls (Pause/Resume, Save clip, Hold to Stop)
    /// (rows 4, 5).
    case showControls
    /// Suppress automatic re-dimming until told otherwise; used while a crash
    /// countdown is active (row 10).
    case suppressRedim(Bool)
    /// Restore the brightness persisted by a previous run's guard, exactly once
    /// (row 14).
    case restorePersistedOriginal
}
