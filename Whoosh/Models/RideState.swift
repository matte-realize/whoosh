import Foundation

/// The explicit ride lifecycle state machine (Requirement 3.5).
///
/// Only the transitions documented in the design are permitted; undefined
/// transitions are safe no-ops rather than crashes. The `RideSessionViewModel`
/// owns an instance of this and reacts to user intents, location events, and
/// clock events.
enum RideState: Equatable, Sendable {
    /// No ride in progress.
    case idle
    /// Actively recording and appending acceptable points.
    case recording
    /// User paused; data retained, no points appended.
    case paused
    /// Was recording, but acceptable updates stalled past the loss timeout.
    case signalLost
    /// Ride finalized and persisted (terminal).
    case finished

    /// The active states a ride can be stopped from (`recording`, `paused`,
    /// `signalLost`), per the transition table.
    var isActive: Bool {
        switch self {
        case .recording, .paused, .signalLost:
            return true
        case .idle, .finished:
            return false
        }
    }
}
