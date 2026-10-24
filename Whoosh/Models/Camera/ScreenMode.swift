import Foundation

/// The ride-mode screen state (rear-camera spec Requirement 10, design
/// "ScreenModeStateMachine"). Drives the true-black, minimum-brightness,
/// touch-locked overlay that makes a rear-mounted phone "look off" while the
/// camera and GPS run. Only the documented transitions are permitted.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`. Deadlines are
/// absolute `Date`s so the screen controller and a watch can tick locally.
enum ScreenMode: Equatable, Codable, Sendable {
    /// Normal brightness and touch; the usual active-ride screen is shown.
    case normal
    /// Mount-grace countdown before dimming; `until` is the deadline.
    case graceCountdown(until: Date)
    /// Dimmed to minimum, touch-locked; only the two-finger unlock is accepted.
    case dimLocked
    /// Temporarily unlocked to show controls; re-dims at `until`.
    case unlockedTemporarily(until: Date)
    /// The app resigned active; brightness restored, guard cleared.
    case suspended
}
