import Foundation

/// The outcome of a notifier dispatch, as reported back into the pure reducer
/// (spec design transition table rows 12–16, fallback matrix). The coordinator
/// classifies a real notifier response/error into one of these before feeding
/// it to the reducer, so the reducer stays pure and deterministic.
enum CrashDispatchOutcome: Equatable, Sendable {
    /// No network at dispatch time (or a definite no-connection failure).
    case offline
    /// At least one recipient reached queued/sent/delivered (Requirement 9.4).
    case success
    /// A retryable backend error (5xx / network) with the same `crashEventId`.
    case retryableError
    /// A non-retryable error (kill switch, cap, invalid, consent, template).
    case nonRetryableError
    /// A timeout where the request may have reached the server — retry **once**
    /// with the same key (Owner resolution O5), then treat as failed.
    case timeoutUnknown
}

/// Events fed to the pure `CrashStateMachine` reducer (spec Requirement 6.1,
/// design "Crash event state machine"). Each transition-table row is driven by
/// one of these. Foundation-only; `Equatable`, `Sendable`.
///
/// Values that a pure reducer cannot generate (a new `crashEventId`, the
/// detection timestamp/offset) are supplied via `CrashReducerContext`, not the
/// event, so the reducer is a deterministic function of (state, event, context).
enum CrashReducerEvent: Equatable, Sendable {
    /// A probable-crash signal from a `CrashDetector` (rows 1–4, 6).
    case detectorSignal(isDrill: Bool)
    /// Evidence capture finished for a `detected` event (row 5).
    case evidenceCaptured
    /// The rider tapped "I'm OK — Cancel" (rows 7, 9, 17, 18, 21).
    case riderCancel
    /// The countdown deadline was reached (rows 8, 9).
    case deadlineReached
    /// The rider tapped "Send now" (row 10).
    case sendNow
    /// Consent was revoked while an event was active (rows 11, 22).
    case consentRevoked
    /// A notifier dispatch resolved with the given outcome (rows 12–16).
    case dispatchResult(CrashDispatchOutcome)
    /// Connectivity was restored or the retry timer fired (row 19).
    case retryTrigger
    /// The stale limit passed while queued/retrying (row 20, 32).
    case staleLimitReached
    /// A per-recipient status poll update arrived after `sent` (row 24).
    case statusPollUpdate
    /// The rider tapped "Tell contacts I'm OK" after a sent alert (row 25).
    case tellContactsImOK
    /// The composer fallback was opened / dismissed / discarded (row 23).
    case composerAction
    /// The app relaunched and found this persisted event (rows 26–33).
    case relaunch
}
