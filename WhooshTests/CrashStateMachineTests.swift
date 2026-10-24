import Foundation
import Testing
@testable import Whoosh

/// Row-by-row tests for the pure `CrashStateMachine` reducer (crash-response
/// task 6, Requirements 6.1–6.9, 8.4, 8.10, 12.1–12.6, 13.5, 13.6, 17.1, 19.2,
/// 19.3, 19.6). One test per row of the design's 34-row transition table, plus
/// a few explicit guard cases. Property-style checks live in
/// `CrashStateMachinePropertyTests`.
struct CrashStateMachineTests {
    private let tuning = CrashResponseTuning()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let eventId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// A context at `now` with overridable arming/connectivity/consent.
    private func ctx(
        now: Date? = nil,
        armed: Bool = true,
        online: Bool = true,
        consentCurrent: Bool = true,
        newEventId: UUID? = nil
    ) -> CrashReducerContext {
        CrashReducerContext(
            now: now ?? t0,
            tuning: tuning,
            armed: armed,
            online: online,
            consentCurrent: consentCurrent,
            newEventId: newEventId ?? eventId
        )
    }

    private func reduce(
        _ state: CrashMachineState,
        _ event: CrashReducerEvent,
        _ context: CrashReducerContext
    ) -> CrashReduction {
        CrashStateMachine.reduce(state, event, context)
    }

    /// A state in `countdown` with a deadline `seconds` after `t0`.
    private func countingDown(seconds: TimeInterval = 30, sentCount: Int = 0, isDrill: Bool = false) -> CrashMachineState {
        CrashMachineState(
            eventState: .countdown,
            eventId: eventId,
            detectedAt: t0,
            isDrill: isDrill,
            deadline: t0.addingTimeInterval(seconds),
            totalCountdownSeconds: seconds,
            perRideSentCount: sentCount
        )
    }

    private func sending(requestInFlight: Bool, attemptCount: Int = 1, isDrill: Bool = false, timeoutRetryUsed: Bool = false) -> CrashMachineState {
        CrashMachineState(
            eventState: .sending,
            eventId: eventId,
            detectedAt: t0,
            isDrill: isDrill,
            attemptCount: attemptCount,
            requestInFlight: requestInFlight,
            timeoutRetryUsed: timeoutRetryUsed,
            outcome: .expired
        )
    }

    // MARK: Row 1 — signal in idle, armed, not suppressed, under cap ⇒ detected

    @Test func row1_signalOpensEvent() {
        let r = reduce(.initial, .detectorSignal(isDrill: false), ctx())
        #expect(r.state.eventState == .detected)
        #expect(r.state.eventId == eventId)
        #expect(r.state.detectedAt == t0)
        #expect(r.effects.contains(.captureEvidence(eventId: eventId)))
        #expect(r.effects.contains(.persist))
    }

    // MARK: Row 2 — signal while not armed ⇒ ignored

    @Test func row2_notArmedIgnored() {
        let r = reduce(.initial, .detectorSignal(isDrill: false), ctx(armed: false))
        #expect(r.state.eventState == .idle)
        #expect(r.effects == [.logIgnored(.notArmed)])
    }

    // MARK: Row 3 — signal inside suppression window ⇒ ignored

    @Test func row3_suppressedIgnored() {
        var resting = CrashMachineState(eventState: .cancelled, suppressedUntil: t0.addingTimeInterval(60))
        resting.eventId = eventId
        let r = reduce(resting, .detectorSignal(isDrill: false), ctx(now: t0.addingTimeInterval(30)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.effects == [.logIgnored(.suppressed)])
    }

    @Test func row3_afterSuppressionWindowNewEventAllowed() {
        let resting = CrashMachineState(eventState: .cancelled, eventId: eventId, suppressedUntil: t0.addingTimeInterval(60))
        let r = reduce(resting, .detectorSignal(isDrill: false), ctx(now: t0.addingTimeInterval(61), newEventId: UUID()))
        #expect(r.state.eventState == .detected)
    }

    // MARK: Row 4 — signal at/over per-ride sent cap ⇒ ignored

    @Test func row4_capReachedIgnored() {
        let resting = CrashMachineState(eventState: .sent, eventId: eventId, perRideSentCount: 1)
        let r = reduce(resting, .detectorSignal(isDrill: false), ctx(now: t0.addingTimeInterval(10_000)))
        #expect(r.state.eventState == .sent)
        #expect(r.effects == [.logIgnored(.capReached)])
    }

    @Test func row4_drillNotCappedEvenAtCap() {
        let resting = CrashMachineState(eventState: .sent, eventId: eventId, perRideSentCount: 1)
        let r = reduce(resting, .detectorSignal(isDrill: true), ctx(now: t0.addingTimeInterval(10_000), newEventId: UUID()))
        #expect(r.state.eventState == .detected)
        #expect(r.state.isDrill)
    }

    // MARK: Row 5 — evidence captured ⇒ countdown

    @Test func row5_evidenceCapturedStartsCountdown() {
        let detected = CrashMachineState(eventState: .detected, eventId: eventId, detectedAt: t0)
        let r = reduce(detected, .evidenceCaptured, ctx())
        #expect(r.state.eventState == .countdown)
        #expect(r.state.deadline == t0.addingTimeInterval(30))
        #expect(r.state.totalCountdownSeconds == 30)
        #expect(r.effects.contains(.startCountdownFeedback(totalSeconds: 30)))
        #expect(r.effects.contains(.scheduleBackupNotification(deadline: t0.addingTimeInterval(30))))
        #expect(r.effects.contains(.presentTakeover))
        #expect(r.effects.contains(.keepScreenAwake))
    }

    // MARK: Row 6 — signal while an event is active ⇒ ignored

    @Test func row6_signalWhileActiveIgnored() {
        for active in [CrashEventState.detected, .countdown, .sending, .queuedOffline, .failed, .fallbackPrompted, .recoveryPrompted] {
            let s = CrashMachineState(eventState: active, eventId: eventId, detectedAt: t0, deadline: t0.addingTimeInterval(30))
            let r = reduce(s, .detectorSignal(isDrill: false), ctx())
            #expect(r.state.eventState == active)
            #expect(r.effects == [.logIgnored(.eventActive)])
        }
    }

    // MARK: Row 7 — cancel before deadline ⇒ cancelled + suppression

    @Test func row7_cancelBeforeDeadline() {
        let r = reduce(countingDown(), .riderCancel, ctx(now: t0.addingTimeInterval(10)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .riderCancelled)
        #expect(r.state.suppressedUntil == t0.addingTimeInterval(10 + 120))
        #expect(r.effects.contains(.stopCountdownFeedback))
        #expect(r.effects.contains(.cancelBackupNotification))
        // No send effect ever.
        #expect(!r.effects.contains { if case .dispatchSend = $0 { return true } else { return false } })
    }

    // MARK: Row 8 — deadline reached ⇒ sending + dispatch

    @Test func row8_deadlineReachedDispatches() {
        let r = reduce(countingDown(), .deadlineReached, ctx(now: t0.addingTimeInterval(30)))
        #expect(r.state.eventState == .sending)
        #expect(r.state.outcome == .expired)
        #expect(r.state.requestInFlight)
        #expect(r.effects.contains(.stopCountdownFeedback))
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: false)))
    }

    // MARK: Row 9 — cancel at/after deadline ⇒ expiry wins (sending)

    @Test func row9_cancelAtDeadlineExpiryWins() {
        // Cancel at exactly the deadline.
        let r = reduce(countingDown(seconds: 30), .riderCancel, ctx(now: t0.addingTimeInterval(30)))
        #expect(r.state.eventState == .sending)
        #expect(r.state.outcome == .expired)
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: false)))
    }

    // MARK: Row 10 — "Send now" ⇒ sending + dispatch

    @Test func row10_sendNowDispatches() {
        let r = reduce(countingDown(), .sendNow, ctx(now: t0.addingTimeInterval(5)))
        #expect(r.state.eventState == .sending)
        #expect(r.state.outcome == .sentNow)
        #expect(r.effects.contains(.stopCountdownFeedback))
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: false)))
    }

    // MARK: Row 11 — consent revoked during countdown ⇒ cancelled, no send

    @Test func row11_consentRevokedDuringCountdown() {
        let r = reduce(countingDown(), .consentRevoked, ctx(now: t0.addingTimeInterval(5)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .consentRevoked)
        #expect(r.effects.contains(.stopCountdownFeedback))
        #expect(!r.effects.contains { if case .dispatchSend = $0 { return true } else { return false } })
    }

    // MARK: Row 12 — dispatch while offline ⇒ queuedOffline

    @Test func row12_dispatchOfflineQueues() {
        // Deadline reached while offline: dispatch path queues instead of sending.
        let r = reduce(countingDown(), .deadlineReached, ctx(now: t0.addingTimeInterval(30), online: false))
        #expect(r.state.eventState == .queuedOffline)
        #expect(r.effects.contains(.presentOfflineBanner))
        #expect(r.effects.contains(.presentComposerFallback))
        #expect(r.effects.contains(.localNotSentNotice))
        #expect(!r.effects.contains { if case .dispatchSend = $0 { return true } else { return false } })
    }

    @Test func row12_dispatchResultOfflineQueues() {
        let r = reduce(sending(requestInFlight: true), .dispatchResult(.offline), ctx())
        #expect(r.state.eventState == .queuedOffline)
        #expect(!r.state.requestInFlight)
        #expect(r.effects.contains(.presentOfflineBanner))
    }

    // MARK: Row 13 — success ⇒ sent, cap+1, suppression, polling

    @Test func row13_successMarksSent() {
        let r = reduce(sending(requestInFlight: true), .dispatchResult(.success), ctx(now: t0.addingTimeInterval(40)))
        #expect(r.state.eventState == .sent)
        #expect(r.state.perRideSentCount == 1)
        #expect(r.state.suppressedUntil == t0.addingTimeInterval(40 + 120))
        #expect(r.effects.contains(.startStatusPolling(eventId: eventId)))
        #expect(r.effects.contains(.cancelBackupNotification))
    }

    @Test func row13_drillSuccessDoesNotConsumeCap() {
        let r = reduce(sending(requestInFlight: true, isDrill: true), .dispatchResult(.success), ctx())
        #expect(r.state.eventState == .sent)
        #expect(r.state.perRideSentCount == 0)
    }

    // MARK: Row 14 — non-retryable error ⇒ failed → fallbackPrompted

    @Test func row14_nonRetryableFails() {
        let r = reduce(sending(requestInFlight: true), .dispatchResult(.nonRetryableError), ctx())
        #expect(r.state.eventState == .fallbackPrompted)
        #expect(r.effects.contains(.presentComposerFallback))
        #expect(r.effects.contains(.localNotSentNotice))
    }

    // MARK: Row 15 — retryable error, attempts left, within stale ⇒ retry scheduled

    @Test func row15_retryableSchedulesRetry() {
        let r = reduce(sending(requestInFlight: true, attemptCount: 1), .dispatchResult(.retryableError), ctx(now: t0.addingTimeInterval(60)))
        #expect(r.state.eventState == .sending)
        #expect(!r.state.requestInFlight)
        // attemptCount is 1 at failure time ⇒ RetryPolicy.delay(forAttempt: 1) == 5 s.
        #expect(r.effects.contains(.scheduleRetry(delay: 5)))
    }

    // MARK: Row 16 — retryable, attempts exhausted ⇒ failed

    @Test func row16_retryableExhaustedFails() {
        let r = reduce(sending(requestInFlight: true, attemptCount: 6), .dispatchResult(.retryableError), ctx(now: t0.addingTimeInterval(60)))
        #expect(r.state.eventState == .fallbackPrompted)
    }

    @Test func row16_retryableStaleFails() {
        let r = reduce(sending(requestInFlight: true, attemptCount: 1), .dispatchResult(.retryableError), ctx(now: t0.addingTimeInterval(31 * 60)))
        #expect(r.state.eventState == .fallbackPrompted)
    }

    // MARK: Row 17 — rider "I'm OK" in retry wait (no request) ⇒ cancelled

    @Test func row17_cancelDuringRetryWait() {
        let r = reduce(sending(requestInFlight: false), .riderCancel, ctx(now: t0.addingTimeInterval(70)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .riderCancelled)
    }

    // MARK: Row 18 — rider "I'm OK" while request in flight ⇒ not cancellable

    @Test func row18_cannotCancelInFlight() {
        let s = sending(requestInFlight: true)
        let r = reduce(s, .riderCancel, ctx(now: t0.addingTimeInterval(70)))
        #expect(r.state.eventState == .sending)
        #expect(r.state == s)
    }

    // MARK: Row 19 — retry trigger while queued, within stale, online ⇒ sending

    @Test func row19_retryTriggerRedispatches() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(queued, .retryTrigger, ctx(now: t0.addingTimeInterval(120), online: true))
        #expect(r.state.eventState == .sending)
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: true)))
    }

    @Test func row19_retryTriggerStaysQueuedWhenOffline() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(queued, .retryTrigger, ctx(now: t0.addingTimeInterval(120), online: false))
        #expect(r.state.eventState == .queuedOffline)
        #expect(!r.effects.contains { if case .dispatchSend = $0 { return true } else { return false } })
    }

    // MARK: Row 20 — queued + stale limit reached ⇒ stale, never auto-send

    @Test func row20_queuedStaleBecomesStale() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(queued, .staleLimitReached, ctx(now: t0.addingTimeInterval(31 * 60)))
        #expect(r.state.eventState == .stale)
        #expect(r.effects.contains(.presentStaleNotice))
        #expect(r.effects.contains(.presentComposerFallback))
    }

    @Test func row20_retryTriggerPastStaleBecomesStale() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(queued, .retryTrigger, ctx(now: t0.addingTimeInterval(31 * 60), online: true))
        #expect(r.state.eventState == .stale)
    }

    // MARK: Row 21 — cancel while queued ⇒ cancelled, retries stop

    @Test func row21_cancelWhileQueued() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0)
        let r = reduce(queued, .riderCancel, ctx(now: t0.addingTimeInterval(100)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .riderCancelled)
    }

    // MARK: Row 22 — consent revoked while queued / retry wait ⇒ cancelled

    @Test func row22_consentRevokedWhileQueued() {
        let queued = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0)
        let r = reduce(queued, .consentRevoked, ctx(now: t0.addingTimeInterval(100)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .consentRevoked)
    }

    @Test func row22_consentRevokedWhileRetryWait() {
        let r = reduce(sending(requestInFlight: false), .consentRevoked, ctx(now: t0.addingTimeInterval(100)))
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.outcome == .consentRevoked)
    }

    // MARK: Row 23 — composer action in fallbackPrompted ⇒ resting, persist

    @Test func row23_composerActionPersists() {
        let s = CrashMachineState(eventState: .fallbackPrompted, eventId: eventId, detectedAt: t0)
        let r = reduce(s, .composerAction, ctx())
        #expect(r.state.eventState == .fallbackPrompted)
        #expect(r.effects == [.persist])
    }

    // MARK: Row 24 — status poll update in sent ⇒ update attempts

    @Test func row24_statusPollUpdates() {
        let s = CrashMachineState(eventState: .sent, eventId: eventId, detectedAt: t0, perRideSentCount: 1)
        let r = reduce(s, .statusPollUpdate, ctx())
        #expect(r.state.eventState == .sent)
        #expect(r.effects.contains(.updateAttempts))
    }

    // MARK: Row 25 — "Tell contacts I'm OK" in sent ⇒ all-clear

    @Test func row25_tellContactsImOK() {
        let s = CrashMachineState(eventState: .sent, eventId: eventId, detectedAt: t0, perRideSentCount: 1)
        let r = reduce(s, .tellContactsImOK, ctx())
        #expect(r.state.eventState == .sent)
        #expect(r.effects.contains(.sendAllClear(eventId: eventId)))
    }

    // MARK: Row 26 — relaunch in countdown, deadline future ⇒ resume countdown

    @Test func row26_relaunchResumesCountdown() {
        let s = countingDown(seconds: 30)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(10)))
        #expect(r.state.eventState == .countdown)
        #expect(r.effects.contains(.presentTakeover))
        #expect(r.effects.contains(.startCountdownFeedback(totalSeconds: 20)))
    }

    // MARK: Row 27 — relaunch in countdown, deadline passed ⇒ recoveryPrompted

    @Test func row27_relaunchPastDeadlinePrompts() {
        let s = countingDown(seconds: 30)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(31)))
        #expect(r.state.eventState == .recoveryPrompted)
        #expect(r.effects.contains(.presentRecoveryPrompt(eventId: eventId)))
    }

    // MARK: Row 28 — recovery "Send now" within stale ⇒ sending

    @Test func row28_recoverySendNow() {
        let s = CrashMachineState(eventState: .recoveryPrompted, eventId: eventId, detectedAt: t0)
        let r = reduce(s, .sendNow, ctx(now: t0.addingTimeInterval(120)))
        #expect(r.state.eventState == .sending)
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: false)))
    }

    @Test func row28_recoverySendNowPastStaleBecomesStale() {
        let s = CrashMachineState(eventState: .recoveryPrompted, eventId: eventId, detectedAt: t0)
        let r = reduce(s, .sendNow, ctx(now: t0.addingTimeInterval(31 * 60)))
        #expect(r.state.eventState == .stale)
    }

    // MARK: Row 29 — recovery "I'm OK"/dismiss ⇒ cancelled

    @Test func row29_recoveryDismiss() {
        let s = CrashMachineState(eventState: .recoveryPrompted, eventId: eventId, detectedAt: t0)
        let r = reduce(s, .riderCancel, ctx(now: t0.addingTimeInterval(120)))
        // Row 29: recovery "I'm OK"/dismiss ⇒ cancelled + suppression; no send.
        #expect(r.state.eventState == .cancelled)
        #expect(r.state.suppressedUntil == t0.addingTimeInterval(120 + 120))
        #expect(!r.effects.contains { if case .dispatchSend = $0 { return true } else { return false } })
    }

    // MARK: Row 30 — relaunch in sending within stale ⇒ resume idempotently

    @Test func row30_relaunchSendingResumes() {
        let s = sending(requestInFlight: true, attemptCount: 1)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(120)))
        #expect(r.state.eventState == .sending)
        #expect(r.effects.contains(.dispatchSend(eventId: eventId, isRetry: true)))
    }

    // MARK: Row 31 — relaunch in queuedOffline within stale ⇒ resume retries

    @Test func row31_relaunchQueuedResumes() {
        let s = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(120)))
        #expect(r.state.eventState == .queuedOffline)
        #expect(r.effects.contains(.presentOfflineBanner))
    }

    // MARK: Row 32 — relaunch in queued/sending past stale ⇒ stale

    @Test func row32_relaunchQueuedPastStaleBecomesStale() {
        let s = CrashMachineState(eventState: .queuedOffline, eventId: eventId, detectedAt: t0, attemptCount: 1)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(31 * 60)))
        #expect(r.state.eventState == .stale)
    }

    @Test func row32_relaunchSendingPastStaleBecomesStale() {
        let s = sending(requestInFlight: true)
        let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(31 * 60)))
        #expect(r.state.eventState == .stale)
    }

    // MARK: Row 33 — relaunch in a resting state ⇒ untouched

    @Test func row33_relaunchRestingUntouched() {
        for resting in [CrashEventState.idle, .cancelled, .sent, .stale, .fallbackPrompted] {
            let s = CrashMachineState(eventState: resting, eventId: eventId, detectedAt: t0)
            let r = reduce(s, .relaunch, ctx(now: t0.addingTimeInterval(120)))
            #expect(r.state.eventState == resting)
            #expect(r.effects.isEmpty)
        }
    }

    // MARK: Row 34 — undefined transitions in idle ⇒ no-op

    @Test func row34_undefinedTransitionsAreNoOps() {
        let idle = CrashMachineState.initial
        for event in [CrashReducerEvent.riderCancel, .sendNow, .deadlineReached, .consentRevoked, .statusPollUpdate, .tellContactsImOK, .composerAction, .retryTrigger, .staleLimitReached, .dispatchResult(.success)] {
            let r = reduce(idle, event, ctx())
            #expect(r.state == idle)
            #expect(r.effects.isEmpty)
        }
    }

    // MARK: O5 — unknown outcome retries exactly once

    @Test func o5_timeoutRetriesOnceThenFails() {
        // First timeout ⇒ one retry.
        let s1 = sending(requestInFlight: true, attemptCount: 1, timeoutRetryUsed: false)
        let r1 = reduce(s1, .dispatchResult(.timeoutUnknown), ctx(now: t0.addingTimeInterval(30)))
        #expect(r1.state.eventState == .sending)
        #expect(r1.state.timeoutRetryUsed)
        #expect(r1.effects.contains { if case .scheduleRetry = $0 { return true } else { return false } })

        // Second timeout ⇒ fail (no more O5 retries).
        let s2 = sending(requestInFlight: true, attemptCount: 2, timeoutRetryUsed: true)
        let r2 = reduce(s2, .dispatchResult(.timeoutUnknown), ctx(now: t0.addingTimeInterval(35)))
        #expect(r2.state.eventState == .fallbackPrompted)
    }
}
