import Foundation

/// The explicit crash-event state machine states (spec Requirement 6.1,
/// design "Crash event state machine"). Only the transitions in the design are
/// permitted; undefined transitions are no-ops, never crashes.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`, `CaseIterable`.
enum CrashEventState: String, Codable, Sendable, CaseIterable {
    /// No crash event in progress.
    case idle
    /// A probable crash was detected; evidence is being captured.
    case detected
    /// The audible/visual/haptic countdown is running.
    case countdown
    /// The rider cancelled, or consent was revoked (resting).
    case cancelled
    /// The alert is being dispatched to the notifier.
    case sending
    /// At least one recipient reached a sent/queued/delivered status (resting).
    case sent
    /// No network at dispatch; the alert is queued and retried.
    case queuedOffline
    /// A non-retryable or exhausted send failed.
    case failed
    /// After a failure/offline resolution, the composer fallback is offered.
    case fallbackPrompted
    /// The app relaunched past a countdown deadline; prompt, never auto-send.
    case recoveryPrompted
    /// The stale limit passed without a successful send (resting); never sent.
    case stale

    /// Active states block new probable-crash signals (Requirement 6.4).
    var isActive: Bool {
        switch self {
        case .detected, .countdown, .sending, .queuedOffline, .failed,
             .fallbackPrompted, .recoveryPrompted:
            return true
        case .idle, .cancelled, .sent, .stale:
            return false
        }
    }
}
