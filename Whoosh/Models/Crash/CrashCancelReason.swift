import Foundation

/// Why a crash event ended without an automatic send (spec design transition
/// table, rows 7/11/17/21/22/29). Recorded in the crash record.
///
/// Foundation-only enum; `Codable`, `Sendable`, `CaseIterable`.
enum CrashCancelReason: String, Codable, Sendable, CaseIterable {
    /// The rider tapped "I'm OK — Cancel".
    case riderCancelled
    /// Consent was revoked while an event was active.
    case consentRevoked
    /// The rider dismissed a relaunch recovery prompt.
    case recoveryDismissed
}

/// How a countdown ended (spec Requirement 8.10). Distinct from the cancel
/// reason: this records the terminal disposition of the countdown itself.
///
/// Foundation-only enum; `Codable`, `Sendable`, `CaseIterable`.
enum CountdownOutcome: String, Codable, Sendable, CaseIterable {
    /// The rider cancelled before the deadline.
    case riderCancelled
    /// The deadline was reached uncancelled.
    case expired
    /// The rider tapped "Send now".
    case sentNow
    /// Consent was revoked during the countdown.
    case consentRevoked
}
