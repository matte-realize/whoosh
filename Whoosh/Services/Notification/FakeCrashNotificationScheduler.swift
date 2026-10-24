import Foundation

/// Scriptable `CrashNotificationScheduler` for tests and previews. Records every
/// scheduling and cancellation so the coordinator's backup-prompt plumbing can
/// be asserted; schedules **nothing** with the real notification center.
///
/// `@MainActor` so its mutable log is race-free (it conforms to the `Sendable`
/// protocol by being main-actor isolated). Tests reach it via `@testable import`.
@MainActor
final class FakeCrashNotificationScheduler: CrashNotificationScheduler {
    /// Deadline prompts scheduled, as `(eventId, deadline)`, in call order.
    private(set) var deadlinePrompts: [(eventId: UUID, deadline: Date)] = []
    /// Event ids a "not sent" notice was scheduled for, in call order.
    private(set) var notSentNotices: [UUID] = []
    /// Event ids `cancel` was called for, in call order.
    private(set) var cancellations: [UUID] = []
    /// Number of authorization requests.
    private(set) var authorizationRequestCount = 0

    /// What `requestAuthorizationIfNeeded()` returns.
    var authorizationGranted: Bool

    init(authorizationGranted: Bool = true) {
        self.authorizationGranted = authorizationGranted
    }

    /// Event ids that currently have a scheduled deadline prompt and no later
    /// cancellation — convenience for "is a backup prompt pending" assertions.
    var pendingDeadlineEventIDs: [UUID] {
        deadlinePrompts.map(\.eventId).filter { id in
            let scheduled = deadlinePrompts.filter { $0.eventId == id }.count
            let cancelled = cancellations.filter { $0 == id }.count
            return scheduled > cancelled
        }
    }

    func scheduleDeadlinePrompt(eventId: UUID, at deadline: Date) {
        deadlinePrompts.append((eventId, deadline))
    }

    func scheduleNotSentNotice(eventId: UUID) {
        notSentNotices.append(eventId)
    }

    func cancel(eventId: UUID) {
        cancellations.append(eventId)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationRequestCount += 1
        return authorizationGranted
    }
}
