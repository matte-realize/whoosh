import Foundation

/// A command sent from an eyes-free surface (watch, audio, shutter remote) to
/// the ride (rear-camera spec Requirement 13, design "Eyes-free surfaces:
/// Commands"). Starting a ride is deliberately **not** a command in v1 — a ride
/// is started and framed on the phone.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`.
enum RideRemoteCommand: Equatable, Codable, Sendable {
    /// Pause recording/tracking (idempotent; ignored in an invalid state).
    case pause
    /// Resume recording/tracking (idempotent).
    case resume
    /// Save a clip from the ring buffer (debounced).
    case saveClip
    /// Stop the ride. Honoured **only** with `confirmedByHold` so an accidental
    /// wrist tap can never end a ride.
    case stop(confirmedByHold: Bool)
    /// Cancel an active crash countdown (crash-response cross-reference).
    case cancelCrashCountdown

    /// Whether this is a `stop` that was confirmed by a hold gesture.
    var isStopConfirmed: Bool {
        if case .stop(let confirmed) = self { return confirmed }
        return false
    }
}
