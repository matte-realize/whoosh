import Foundation

/// The context the pure `ScreenModeStateMachine` reducer needs that is not part
/// of `ScreenMode` itself (rear-camera spec design "ScreenModeStateMachine").
/// Keeps the reducer pure: it reads no clock, no `UIScreen`, and no global state
/// — everything comes in here, and the deadlines it produces are absolute
/// `Date`s derived from `now`.
///
/// Foundation-only value type (Models layer): `Equatable`, `Sendable`.
struct ScreenModeContext: Equatable, Sendable {
    /// The current instant (the `RideModeController` passes `clock.now()`).
    var now: Date
    /// All ride-mode timing/brightness defaults (mount grace, unlock inactivity
    /// window, dim brightness).
    var tuning: RideCameraTuning
    /// Whether a ride is currently active (guards rows 9, 11, 14).
    var rideActive: Bool
    /// Whether ride mode is enabled for this ride and the camera feature is on
    /// (guards rows 1, 9, 11).
    var rideModeEnabled: Bool

    init(
        now: Date,
        tuning: RideCameraTuning = RideCameraTuning(),
        rideActive: Bool,
        rideModeEnabled: Bool
    ) {
        self.now = now
        self.tuning = tuning
        self.rideActive = rideActive
        self.rideModeEnabled = rideModeEnabled
    }

    /// The grace-countdown deadline: `now + mountGrace` (row 1).
    var graceDeadline: Date { now.addingTimeInterval(tuning.mountGrace) }

    /// The temporary-unlock deadline: `now + unlockInactivityWindow` (rows 4–6, 9).
    var unlockDeadline: Date { now.addingTimeInterval(tuning.unlockInactivityWindow) }
}

/// The result of one `ScreenModeStateMachine.reduce` step: the next screen mode
/// and the ordered effects the controller executes. Mirrors `CrashReduction`.
/// Foundation-only; `Equatable`, `Sendable`.
struct ScreenModeReduction: Equatable, Sendable {
    var state: ScreenMode
    var effects: [ScreenModeEffect]

    init(state: ScreenMode, effects: [ScreenModeEffect] = []) {
        self.state = state
        self.effects = effects
    }
}
