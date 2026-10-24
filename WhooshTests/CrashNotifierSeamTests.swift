import Foundation
import Testing
@testable import Whoosh

/// Tests for the task 8 seams' fakes: `CrashNotifier` (Noop + Fake),
/// `CrashNotificationScheduler` fake, `CountdownFeedback` (Noop + Fake), and
/// `ConnectivityMonitor` fake. They cover each fake's scripting API and call
/// counts, and the typed-error classification.
@MainActor
struct CrashNotifierSeamTests {

    private func request(
        kind: CrashMessageKind = .crashAlert,
        recipients: [CrashNotificationRecipient] = [CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")]
    ) -> CrashNotificationRequest {
        CrashNotificationRequest(
            crashEventId: UUID(),
            kind: kind,
            riderLabel: "Alex",
            detectedAt: Date(timeIntervalSince1970: 0),
            utcOffsetMinutes: -240,
            delayedSeconds: 0,
            location: .unavailable,
            recipients: recipients,
            consentVersion: 1,
            templateVersion: 1
        )
    }

    // MARK: Typed errors

    @Test func errorCodeDefaultRetryability() {
        #expect(CrashNotifierError(.timeout).isRetryable)
        #expect(CrashNotifierError(.serverError).isRetryable)
        #expect(CrashNotifierError(.unauthenticated).isRetryable)
        #expect(CrashNotifierError(.noConnection).isRetryable)
        #expect(CrashNotifierError(.unknown).isRetryable)
        #expect(!CrashNotifierError(.invalidRequest).isRetryable)
        #expect(!CrashNotifierError(.rateLimited).isRetryable)
        #expect(!CrashNotifierError(.serviceDisabled).isRetryable)
        #expect(!CrashNotifierError(.idempotencyConflict).isRetryable)
    }

    @Test func errorCanOverrideRetryability() {
        let err = CrashNotifierError(code: .invalidRequest, isRetryable: true)
        #expect(err.isRetryable)
    }

    // MARK: NoopCrashNotifier

    @Test func noopNotifierThrowsServiceDisabled() async {
        let notifier = NoopCrashNotifier()
        await #expect(throws: CrashNotifierError(.serviceDisabled)) {
            _ = try await notifier.send(request())
        }
        await #expect(throws: CrashNotifierError(.serviceDisabled)) {
            _ = try await notifier.status(crashEventId: UUID(), kind: .crashAlert)
        }
    }

    // MARK: FakeCrashNotifier scripting

    @Test func fakeNotifierScriptedSuccess() async throws {
        let recipient = CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")
        let req = request(recipients: [recipient])
        let notifier = FakeCrashNotifier(
            sendBehavior: .allQueued([recipient], at: Date(timeIntervalSince1970: 10))
        )
        let result = try await notifier.send(req)
        #expect(result.recipients.count == 1)
        #expect(result.recipients.first?.status == .queued)
        #expect(notifier.sendCallCount == 1)
        #expect(notifier.sendRequests.first?.crashEventId == req.crashEventId)
    }

    @Test func fakeNotifierPerCodeFailure() async {
        let notifier = FakeCrashNotifier(sendBehavior: .failure(CrashNotifierError(.rateLimited)))
        await #expect(throws: CrashNotifierError(.rateLimited)) {
            _ = try await notifier.send(request())
        }
        #expect(notifier.sendCallCount == 1)
    }

    @Test func fakeNotifierTimeout() async {
        let notifier = FakeCrashNotifier(sendBehavior: .timeout)
        await #expect(throws: CrashNotifierError(.timeout)) {
            _ = try await notifier.send(request())
        }
    }

    @Test func fakeNotifierQueuedBehaviorSequence() async throws {
        let recipient = CrashNotificationRecipient(recipientRef: UUID(), e164: "+16175550123")
        let notifier = FakeCrashNotifier()
        notifier.sendBehaviors = [
            .failure(CrashNotifierError(.serverError)),
            .allQueued([recipient], at: Date(timeIntervalSince1970: 5))
        ]
        // First call: scripted retryable failure.
        await #expect(throws: CrashNotifierError(.serverError)) {
            _ = try await notifier.send(request(recipients: [recipient]))
        }
        // Second call: success.
        let result = try await notifier.send(request(recipients: [recipient]))
        #expect(result.recipients.first?.status == .queued)
        #expect(notifier.sendCallCount == 2)
    }

    @Test func fakeNotifierDelayedDeliveryStatus() async throws {
        let ref = UUID()
        let eventId = UUID()
        let notifier = FakeCrashNotifier()
        notifier.statusResults[eventId] = CrashNotificationResult(
            crashEventId: eventId,
            kind: .crashAlert,
            deduplicated: false,
            recipients: [CrashRecipientResult(recipientRef: ref, status: .delivered, segments: 4, updatedAt: Date(timeIntervalSince1970: 60))]
        )
        let result = try await notifier.status(crashEventId: eventId, kind: .crashAlert)
        #expect(result.recipients.first?.status == .delivered)
        #expect(notifier.statusCallCount == 1)
        #expect(notifier.statusQueries.first?.crashEventId == eventId)
    }
}

@MainActor
struct CrashNotificationSchedulerFakeTests {

    @Test func recordsDeadlinePromptsAndCancellations() {
        let scheduler = FakeCrashNotificationScheduler()
        let id = UUID()
        let deadline = Date(timeIntervalSince1970: 30)
        scheduler.scheduleDeadlinePrompt(eventId: id, at: deadline)
        #expect(scheduler.deadlinePrompts.count == 1)
        #expect(scheduler.pendingDeadlineEventIDs.contains(id))
        scheduler.cancel(eventId: id)
        #expect(!scheduler.pendingDeadlineEventIDs.contains(id))
    }

    @Test func recordsNotSentNotices() {
        let scheduler = FakeCrashNotificationScheduler()
        let id = UUID()
        scheduler.scheduleNotSentNotice(eventId: id)
        #expect(scheduler.notSentNotices == [id])
    }

    @Test func authorizationReturnsScriptedValueAndCounts() async {
        let granted = FakeCrashNotificationScheduler(authorizationGranted: true)
        #expect(await granted.requestAuthorizationIfNeeded())
        let denied = FakeCrashNotificationScheduler(authorizationGranted: false)
        #expect(await denied.requestAuthorizationIfNeeded() == false)
        #expect(denied.authorizationRequestCount == 1)
    }
}

@MainActor
struct CountdownFeedbackFakeTests {

    @Test func noopFeedbackDoesNothing() {
        let feedback = NoopCountdownFeedback()
        feedback.begin(totalSeconds: 30)
        feedback.tick(remaining: 29)
        feedback.end(reason: .cancelled)
        // No state to assert; just proves the Noop compiles and runs.
    }

    @Test func fakeFeedbackRecordsBeginTickEnd() {
        let feedback = FakeCountdownFeedback()
        feedback.begin(totalSeconds: 30)
        feedback.tick(remaining: 29)
        feedback.tick(remaining: 28)
        feedback.end(reason: .expired)
        #expect(feedback.beginTotals == [30])
        #expect(feedback.tickRemainders == [29, 28])
        #expect(feedback.endReasons == [.expired])
    }

    @Test func fakeFeedbackEndIsIdempotent() {
        let feedback = FakeCountdownFeedback()
        feedback.begin(totalSeconds: 15)
        feedback.end(reason: .cancelled)
        feedback.end(reason: .cancelled)
        #expect(feedback.effectiveEndCount == 1)
        #expect(feedback.endReasons.count == 2) // both calls recorded
        #expect(!feedback.isActive)
    }
}

@MainActor
struct ConnectivityMonitorFakeTests {

    @Test func fakeStartsAndStops() {
        let monitor = FakeConnectivityMonitor(isOnline: true)
        #expect(monitor.isOnline)
        #expect(!monitor.isObserving)
        monitor.start()
        #expect(monitor.isObserving)
        monitor.stop()
        #expect(!monitor.isObserving)
    }

    @Test func fakeFiresOnChangeOnlyOnTransitionWhileObserving() {
        let monitor = FakeConnectivityMonitor(isOnline: true)
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }

        // Not observing: no delivery.
        monitor.setOnline(false)
        #expect(changes.isEmpty)
        #expect(!monitor.isOnline)

        monitor.start()
        monitor.setOnline(true)
        monitor.setOnline(true) // no change: no delivery
        monitor.setOnline(false)
        #expect(changes == [true, false])
        #expect(monitor.changeDeliveryCount == 2)
    }
}
