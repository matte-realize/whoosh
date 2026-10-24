import Foundation

/// Why a probable-crash signal was ignored by the reducer (spec design
/// transition table rows 2–6). Logged for the audit trail; never a crash.
enum CrashIgnoreReason: String, Equatable, Sendable, CaseIterable {
    /// Not armed: ride state, consent, label, or contacts disallow it (row 2).
    case notArmed
    /// Inside the suppression window after a cancel/send (row 3).
    case suppressed
    /// The per-ride sent-alert cap is reached (row 4).
    case capReached
    /// An event is already active (rows 6, FP-4).
    case eventActive
}

/// Effects produced by the pure `CrashStateMachine` reducer — **data, not
/// actions** (spec design "Pure functions": "Effects are data … executed by the
/// coordinator"). The reducer never performs I/O; the coordinator interprets
/// these. Foundation-only; `Equatable`, `Sendable`.
///
/// There is deliberately **no call/dial effect** anywhere in this type: Whoosh
/// never auto-calls emergency services (Requirement 17.1). "Call 911" exists
/// only as a rider-tapped control in `Features/Emergency`.
enum CrashEffect: Equatable, Sendable {
    /// A new event was detected: capture timestamp/offset/location snapshot and
    /// ask the footage buffer to preserve, then persist (row 1).
    case captureEvidence(eventId: UUID)
    /// Start the audible/visual/haptic countdown feedback (row 5).
    case startCountdownFeedback(totalSeconds: TimeInterval)
    /// Stop all countdown feedback (rows 7, 8, 10, 11).
    case stopCountdownFeedback
    /// Schedule the time-sensitive backup notification at the deadline (row 5).
    case scheduleBackupNotification(deadline: Date)
    /// Cancel the backup notification (rows 7, 11, 13).
    case cancelBackupNotification
    /// Present the full-screen countdown takeover (row 5).
    case presentTakeover
    /// Keep the screen awake for the countdown (row 5).
    case keepScreenAwake
    /// Dispatch the alert send to the notifier. `isRetry` is false for the
    /// initial send and true for a backoff/offline/timeout retry that reuses the
    /// same `crashEventId` (rows 8, 10, 15, 19, 28). The duplicate-prevention
    /// invariant: at most **one** `isRetry == false` dispatch per event.
    case dispatchSend(eventId: UUID, isRetry: Bool)
    /// Schedule the next retry after `delay` (rows 12, 15).
    case scheduleRetry(delay: TimeInterval)
    /// Start polling per-recipient delivery status (row 13).
    case startStatusPolling(eventId: UUID)
    /// Present the "Tap to text <contact> now" composer fallback (rows 14, 16, 20).
    case presentComposerFallback
    /// Present the queued-offline banner + "I'm OK — cancel alert" (row 12).
    case presentOfflineBanner
    /// Present the stale notice + composer fallback + discard (row 20).
    case presentStaleNotice
    /// Show the local "alert not sent" notification (rows 12, 14).
    case localNotSentNotice
    /// Send the all-clear message for the same event (row 25).
    case sendAllClear(eventId: UUID)
    /// Present the relaunch recovery prompt (row 27).
    case presentRecoveryPrompt(eventId: UUID)
    /// Update stored per-recipient attempts from a status poll (row 24).
    case updateAttempts
    /// Persist the current state/record (most transitions).
    case persist
    /// A probable-crash signal was ignored; log the reason (rows 2–4, 6).
    case logIgnored(CrashIgnoreReason)
}
