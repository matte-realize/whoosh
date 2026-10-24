import Foundation

/// Schedules the **backup** time-sensitive local notifications for a crash
/// countdown (spec design "Execution model" O1(c), Requirement 13.3). This is a
/// backup prompt only: a local notification can draw the rider's attention at
/// the deadline even if the app is suspended, but it can **never send or cancel
/// an alert by itself** — it only prompts. The rider can disable notifications,
/// so it is not a guarantee.
///
/// The concrete implementation (a later task) wraps `UNUserNotificationCenter`;
/// `FakeCrashNotificationScheduler` backs the tests.
///
/// ## Contract
/// - **Backup only.** Scheduling a prompt is not sending an alert. Nothing
///   automatic happens from a notification; it can only prompt the rider.
/// - **Idempotent cancel.** `cancel(eventId:)` is safe to call for an unknown
///   event id.
/// - **Permission, honestly.** `requestAuthorizationIfNeeded()` requests
///   notification authorization only when the rider enables crash alerts, after
///   an in-app explanation; a denial degrades to "no backup prompt", documented
///   in setup.
///
/// `Sendable`-friendly; the concrete type is a reference type delivering on the
/// main actor.
protocol CrashNotificationScheduler: Sendable {
    /// Schedule a backup prompt at the countdown deadline for `eventId`.
    func scheduleDeadlinePrompt(eventId: UUID, at deadline: Date)

    /// Schedule a local "alert not sent" notice for `eventId` (offline/failed).
    func scheduleNotSentNotice(eventId: UUID)

    /// Cancel any scheduled notifications for `eventId`. Idempotent.
    func cancel(eventId: UUID)

    /// Request notification authorization if not already determined. Returns
    /// whether authorization is granted. A denial is not an error.
    func requestAuthorizationIfNeeded() async -> Bool
}
