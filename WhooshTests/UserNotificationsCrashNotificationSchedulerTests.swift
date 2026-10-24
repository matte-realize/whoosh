import Foundation
import UserNotifications
import Testing
@testable import Whoosh

/// Tests for `UserNotificationsCrashNotificationScheduler` (crash-response task
/// 21) using an injected recording `Center` double — no real
/// `UNUserNotificationCenter`, no entitlement, no device. Assert the request
/// identifiers, content, trigger timing, interruption level, and cancellation.
@MainActor
struct UserNotificationsCrashNotificationSchedulerTests {

    /// Records every call the scheduler makes to the notification center.
    final class RecordingCenter: UserNotificationsCrashNotificationScheduler.Center, @unchecked Sendable {
        var added: [UNNotificationRequest] = []
        var removedPending: [[String]] = []
        var removedDelivered: [[String]] = []
        var authorizationRequests = 0
        var authorizationResult: Bool

        init(authorizationResult: Bool = true) {
            self.authorizationResult = authorizationResult
        }

        func add(_ request: UNNotificationRequest) { added.append(request) }
        func removePendingRequests(withIdentifiers identifiers: [String]) { removedPending.append(identifiers) }
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { removedDelivered.append(identifiers) }
        func requestAuthorization() async -> Bool {
            authorizationRequests += 1
            return authorizationResult
        }
    }

    static let eventId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func deadlinePromptSchedulesTimeSensitiveRequestWithFutureTrigger() throws {
        let center = RecordingCenter()
        let scheduler = UserNotificationsCrashNotificationScheduler(center: center)
        let deadline = Date().addingTimeInterval(30)

        scheduler.scheduleDeadlinePrompt(eventId: Self.eventId, at: deadline)

        #expect(center.added.count == 1)
        let request = try #require(center.added.first)
        #expect(request.identifier == UserNotificationsCrashNotificationScheduler.deadlineID(Self.eventId))
        #expect(request.content.interruptionLevel == .timeSensitive)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval > 1)        // roughly the deadline
        #expect(trigger.repeats == false)
        // Backup-only, honest copy.
        #expect(request.content.body.contains("can't guarantee detection or delivery"))
    }

    @Test func deadlinePromptClampsPastDeadlineToPositiveInterval() throws {
        let center = RecordingCenter()
        let scheduler = UserNotificationsCrashNotificationScheduler(center: center)
        // A deadline already in the past still yields a valid (>=1 s) trigger.
        scheduler.scheduleDeadlinePrompt(eventId: Self.eventId, at: Date().addingTimeInterval(-10))
        let trigger = try #require(center.added.first?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval >= 1)
    }

    @Test func notSentNoticeSchedulesPromptlyWithOwnIdentifier() throws {
        let center = RecordingCenter()
        let scheduler = UserNotificationsCrashNotificationScheduler(center: center)
        scheduler.scheduleNotSentNotice(eventId: Self.eventId)

        let request = try #require(center.added.first)
        #expect(request.identifier == UserNotificationsCrashNotificationScheduler.notSentID(Self.eventId))
        #expect(request.content.title == "Alert not sent")
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval >= 1)
    }

    @Test func cancelRemovesBothPendingAndDeliveredForTheEvent() {
        let center = RecordingCenter()
        let scheduler = UserNotificationsCrashNotificationScheduler(center: center)
        scheduler.cancel(eventId: Self.eventId)

        let expected = [
            UserNotificationsCrashNotificationScheduler.deadlineID(Self.eventId),
            UserNotificationsCrashNotificationScheduler.notSentID(Self.eventId),
        ]
        #expect(center.removedPending.first == expected)
        #expect(center.removedDelivered.first == expected)
    }

    @Test func authorizationIsForwardedToTheCenter() async {
        let center = RecordingCenter(authorizationResult: true)
        let scheduler = UserNotificationsCrashNotificationScheduler(center: center)
        let granted = await scheduler.requestAuthorizationIfNeeded()
        #expect(granted)
        #expect(center.authorizationRequests == 1)

        let denyingCenter = RecordingCenter(authorizationResult: false)
        let denyingScheduler = UserNotificationsCrashNotificationScheduler(center: denyingCenter)
        let denied = await denyingScheduler.requestAuthorizationIfNeeded()
        #expect(!denied)
    }
}
