import Foundation
import UserNotifications

/// The shipping `CrashNotificationScheduler` backed by `UNUserNotificationCenter`
/// (spec Requirement 13.3, design "Execution model" O1(c), crash-response
/// task 21).
///
/// It schedules **backup** time-sensitive local notifications only: a prompt at
/// the countdown deadline and an "alert not sent" notice for the offline/failed
/// cases. A local notification can draw the rider's attention even when the app
/// is suspended, but it can **never send or cancel an alert by itself** — it
/// only prompts (Requirement 13.3). The rider can disable notifications, so this
/// is a backup, not a guarantee; Whoosh cannot guarantee detection or delivery.
///
/// This type performs **no network**: `UserNotifications` is a local OS service.
/// Honest copy only: no claim that Whoosh reached emergency services (it never
/// does) or that help is coming.
///
/// `@unchecked Sendable`: `UNUserNotificationCenter` is thread-safe and this
/// wrapper holds only immutable configuration; all calls are lightweight and
/// safe to make from the main actor.
final class UserNotificationsCrashNotificationScheduler: CrashNotificationScheduler, @unchecked Sendable {
    /// Abstracts the single `UNUserNotificationCenter` method set we use so the
    /// scheduler can be unit-tested against a recording double without the real
    /// notification center (which requires an app bundle and entitlement).
    protocol Center: Sendable {
        func add(_ request: UNNotificationRequest)
        func removePendingRequests(withIdentifiers identifiers: [String])
        func removeDeliveredNotifications(withIdentifiers identifiers: [String])
        func requestAuthorization() async -> Bool
    }

    private let center: Center

    /// The `interruptionLevel` used for the deadline prompt. A stored property
    /// (not a literal) so the Critical Alerts follow-up (Requirement 21.1) is a
    /// one-property change after Apple approval.
    private let deadlineInterruptionLevel: UNNotificationInterruptionLevel

    init(
        center: Center = LiveCenter(),
        deadlineInterruptionLevel: UNNotificationInterruptionLevel = .timeSensitive
    ) {
        self.center = center
        self.deadlineInterruptionLevel = deadlineInterruptionLevel
    }

    // MARK: - Identifiers

    /// Notification identifier for an event's deadline prompt.
    static func deadlineID(_ eventId: UUID) -> String { "whoosh.crash.deadline.\(eventId.uuidString)" }
    /// Notification identifier for an event's "not sent" notice.
    static func notSentID(_ eventId: UUID) -> String { "whoosh.crash.notsent.\(eventId.uuidString)" }

    // MARK: - CrashNotificationScheduler

    func scheduleDeadlinePrompt(eventId: UUID, at deadline: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Crash countdown"
        // Honest, backup-only copy: it prompts; it does not send or confirm.
        content.body = "Open Whoosh to cancel the alert or let it send. Whoosh can't guarantee detection or delivery."
        content.interruptionLevel = deadlineInterruptionLevel
        content.sound = .default

        let interval = max(1, deadline.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.deadlineID(eventId),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func scheduleNotSentNotice(eventId: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Alert not sent"
        content.body = "Open Whoosh to text your contact or cancel. Whoosh can't guarantee detection or delivery."
        content.interruptionLevel = deadlineInterruptionLevel
        content.sound = .default

        // Deliver promptly (a backup nudge, not timed to a deadline).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notSentID(eventId),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancel(eventId: UUID) {
        let ids = [Self.deadlineID(eventId), Self.notSentID(eventId)]
        center.removePendingRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await center.requestAuthorization()
    }

    // MARK: - Live center

    /// The real `UNUserNotificationCenter`-backed `Center`.
    struct LiveCenter: Center {
        func add(_ request: UNNotificationRequest) {
            UNUserNotificationCenter.current().add(request)
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        func requestAuthorization() async -> Bool {
            let center = UNUserNotificationCenter.current()
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            return (try? await center.requestAuthorization(options: options)) ?? false
        }
    }
}
