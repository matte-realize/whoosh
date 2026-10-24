import Foundation

/// Inputs to the pure `ScreenModeStateMachine` reducer (rear-camera spec
/// Requirement 10, design "ScreenModeStateMachine" 15-row table). One case per
/// distinct event in that table; the reducer maps `(state, event, context)` to a
/// next `ScreenMode` and a list of `ScreenModeEffect`s.
///
/// Foundation-only enum (Models layer): `Equatable`, `Sendable`. The reducer
/// reads no clock — any instant it needs comes in through `ScreenModeContext`,
/// and deadlines it produces are absolute `Date`s derived from `context.now`.
enum ScreenModeEvent: Equatable, Sendable {
    /// A ride started (row 1). Only enters the grace countdown when ride mode and
    /// the camera feature are on (guarded by the context).
    case rideStarted
    /// The rider tapped "Dim now" during the grace countdown (row 2).
    case dimNow
    /// The grace countdown elapsed (row 2); same outcome as "Dim now".
    case graceElapsed
    /// The rider tapped "Keep screen on" during the grace countdown (row 3);
    /// ride mode is off for this ride.
    case keepScreenOn
    /// The two-finger long-press unlock gesture completed (row 4).
    case twoFingerHoldCompleted
    /// The VoiceOver "Unlock controls" custom action fired (row 5).
    case accessibilityUnlock
    /// Touch activity while temporarily unlocked (row 6); extends the window.
    case touchActivity
    /// The temporary-unlock inactivity deadline was reached (row 7); re-dim.
    case unlockDeadlineReached
    /// The app resigned active (row 8); restore brightness, clear the guard.
    case appResignedActive
    /// The app became active again (row 9).
    case appBecameActive
    /// A crash countdown started (row 10); force full brightness and unlock.
    case crashCountdownStarted
    /// A crash countdown ended (row 11).
    case crashCountdownEnded
    /// The ride ended (row 12); restore brightness, clear the guard.
    case rideEnded
    /// The system brightness changed externally (row 13); `value` is the new
    /// reading (0...1). `riderInitiated` is true when the rider changed it
    /// deliberately while unlocked (then it is left alone).
    case systemBrightnessChanged(value: Double, riderInitiated: Bool)
    /// The app launched while a dim guard from a previous run is still persisted
    /// (row 14); restore the saved original once.
    case launchWithActiveGuard
}
