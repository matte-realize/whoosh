import Foundation

/// The reply to a `RideRemoteCommand` sent from an eyes-free surface
/// (rear-camera spec Requirement 13.2, design "Eyes-free surfaces: Commands").
/// The surface uses it to confirm (a haptic tick) or explain (a short notice)
/// what happened, so a wrist tap is never silently lost.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`.
enum RideRemoteCommandReply: Equatable, Codable, Sendable {
    /// The command was applied.
    case accepted
    /// The command was not applied, with a reason to surface.
    case ignored(reason: Reason)

    /// Why a command was ignored.
    enum Reason: String, Equatable, Codable, Sendable, CaseIterable {
        /// The command does not apply in the current ride state (idempotent/no-op).
        case invalidState = "invalid_state"
        /// A `stop` that was not confirmed by a deliberate hold.
        case notConfirmed = "not_confirmed"
        /// A `saveClip` that found nothing to save.
        case nothingToSave = "nothing_to_save"
        /// No active crash countdown to cancel.
        case noActiveCountdown = "no_active_countdown"
    }
}
