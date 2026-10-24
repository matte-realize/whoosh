import Foundation

/// The pure crash-event reducer: `(state, event, context) → (state, [effects])`
/// implementing every row of the design's transition table (spec Requirement
/// 6.1–6.9, 8.4, 8.10, 12.1–12.6, 13.5, 13.6, 17.1, 19.2, 19.3, 19.6).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). It performs
/// no I/O, generates no ids, and reads no clock; everything it needs comes in
/// via `CrashReducerContext`. Effects are returned as **data** for the
/// coordinator to execute.
///
/// Invariants enforced here (defense in depth, design "Duplicate-prevention
/// layers"):
/// - At most **one** `dispatchSend(isRetry: false)` per event (no double initial
///   send); further sends are retries that reuse the same `crashEventId`.
/// - Undefined transitions are **no-ops** (row 34), never crashes.
/// - No effect is a call/dial action — Whoosh never auto-calls (Requirement 17.1).
enum CrashStateMachine {
    /// Reduce one event. Returns the next state and ordered effects.
    static func reduce(
        _ state: CrashMachineState,
        _ event: CrashReducerEvent,
        _ context: CrashReducerContext
    ) -> CrashReduction {
        switch event {
        case let .detectorSignal(isDrill):
            return reduceSignal(state, isDrill: isDrill, context: context)
        case .evidenceCaptured:
            return reduceEvidenceCaptured(state, context: context)
        case .riderCancel:
            return reduceRiderCancel(state, context: context)
        case .deadlineReached:
            return reduceDeadlineReached(state, context: context)
        case .sendNow:
            return reduceSendNow(state, context: context)
        case .consentRevoked:
            return reduceConsentRevoked(state, context: context)
        case let .dispatchResult(outcome):
            return reduceDispatchResult(state, outcome: outcome, context: context)
        case .retryTrigger:
            return reduceRetryTrigger(state, context: context)
        case .staleLimitReached:
            return reduceStaleLimitReached(state, context: context)
        case .statusPollUpdate:
            return reduceStatusPollUpdate(state, context: context)
        case .tellContactsImOK:
            return reduceTellContactsImOK(state, context: context)
        case .composerAction:
            return reduceComposerAction(state, context: context)
        case .relaunch:
            return reduceRelaunch(state, context: context)
        }
    }

    // MARK: - detector signal (rows 1–4, 6)

    private static func reduceSignal(
        _ state: CrashMachineState,
        isDrill: Bool,
        context: CrashReducerContext
    ) -> CrashReduction {
        // Row 6: an event is already active ⇒ ignore.
        if state.eventState.isActive {
            return noOp(state, log: .eventActive)
        }
        // Row 2: not armed ⇒ ignore.
        guard context.armed else {
            return noOp(state, log: .notArmed)
        }
        // Row 3: inside the suppression window ⇒ ignore.
        if state.isSuppressed(at: context.now) {
            return noOp(state, log: .suppressed)
        }
        // Row 4: per-ride *sent* cap reached ⇒ ignore (drills never consume the
        // cap, so a drill signal is allowed even at the cap).
        if !isDrill, state.perRideSentCount >= context.tuning.maxAutomaticAlertsPerRide {
            return noOp(state, log: .capReached)
        }
        // Row 1: open a new event.
        var next = state
        next.eventState = .detected
        next.eventId = context.newEventId
        next.detectedAt = context.now
        next.isDrill = isDrill
        next.deadline = nil
        next.totalCountdownSeconds = nil
        next.attemptCount = 0
        next.requestInFlight = false
        next.timeoutRetryUsed = false
        next.outcome = nil
        return CrashReduction(
            state: next,
            effects: [.captureEvidence(eventId: context.newEventId), .persist]
        )
    }

    // MARK: - evidence captured (row 5)

    private static func reduceEvidenceCaptured(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .detected else { return noOp(state) }
        let total = context.tuning.clampCountdown(context.tuning.countdownSeconds)
        let deadline = context.now.addingTimeInterval(total)
        var next = state
        next.eventState = .countdown
        next.deadline = deadline
        next.totalCountdownSeconds = total
        return CrashReduction(
            state: next,
            effects: [
                .startCountdownFeedback(totalSeconds: total),
                .scheduleBackupNotification(deadline: deadline),
                .keepScreenAwake,
                .presentTakeover,
                .persist,
            ]
        )
    }

    // MARK: - rider cancel (rows 7, 9, 17, 18, 21)

    private static func reduceRiderCancel(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .countdown:
            // Row 9: cancel at or past the deadline loses the tie — expiry wins.
            if let deadline = state.deadline, context.now >= deadline {
                return reduceDeadlineReached(state, context: context)
            }
            // Row 7: cancel before the deadline.
            return cancel(state, reason: .riderCancelled, context: context, fromCountdown: true)
        case .sending:
            // Row 18: a request in flight is not cancellable.
            if state.requestInFlight {
                return noOp(state)
            }
            // Row 17: in a retry wait with no request in flight ⇒ cancel, stop retries.
            return cancel(state, reason: .riderCancelled, context: context, fromCountdown: false)
        case .queuedOffline:
            // Row 21: cancel while queued ⇒ cancelled, retries stop.
            return cancel(state, reason: .riderCancelled, context: context, fromCountdown: false)
        case .recoveryPrompted:
            // Row 29: recovery "I'm OK" / dismiss ⇒ cancelled (recoveryDismissed).
            return cancel(state, reason: .recoveryDismissed, context: context, fromCountdown: false)
        default:
            // Row 34: undefined (e.g. idle) ⇒ no-op.
            return noOp(state)
        }
    }

    // MARK: - deadline reached (rows 8, 9)

    private static func reduceDeadlineReached(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .countdown else { return noOp(state) }
        var next = state
        next.eventState = .sending
        next.outcome = .expired
        return dispatchInitial(next, context: context, extraLeadingEffects: [.stopCountdownFeedback])
    }

    // MARK: - send now (row 10)

    private static func reduceSendNow(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .countdown:
            var next = state
            next.eventState = .sending
            next.outcome = .sentNow
            return dispatchInitial(next, context: context, extraLeadingEffects: [.stopCountdownFeedback])
        case .recoveryPrompted:
            // Row 28: recovery "Send now" within the stale limit (delayed wording).
            guard let detectedAt = state.detectedAt,
                  RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: context.now, tuning: context.tuning)
            else {
                return toStale(state)
            }
            var next = state
            next.eventState = .sending
            next.outcome = .expired
            return dispatchInitial(next, context: context, extraLeadingEffects: [])
        default:
            return noOp(state)
        }
    }

    // MARK: - consent revoked (rows 11, 22)

    private static func reduceConsentRevoked(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .countdown:
            return cancel(state, reason: .consentRevoked, context: context, fromCountdown: true)
        case .queuedOffline:
            return cancel(state, reason: .consentRevoked, context: context, fromCountdown: false)
        case .sending:
            // Row 22 covers the retry-wait; an in-flight request cannot be unsent,
            // but we stop future retries and mark the outcome.
            if state.requestInFlight { return noOp(state) }
            return cancel(state, reason: .consentRevoked, context: context, fromCountdown: false)
        default:
            return noOp(state)
        }
    }

    // MARK: - dispatch result (rows 12–16)

    private static func reduceDispatchResult(
        _ state: CrashMachineState,
        outcome: CrashDispatchOutcome,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .sending else { return noOp(state) }
        var next = state
        next.requestInFlight = false

        switch outcome {
        case .offline:
            // Row 12: queue offline, show banner + composer + local notice.
            next.eventState = .queuedOffline
            return CrashReduction(
                state: next,
                effects: [
                    .persist,
                    .presentOfflineBanner,
                    .presentComposerFallback,
                    .localNotSentNotice,
                    .cancelBackupNotification,
                ]
            )

        case .success:
            // Row 13: at least one recipient reached a sent status.
            next.eventState = .sent
            if !next.isDrill {
                next.perRideSentCount += 1
            }
            next.suppressedUntil = context.now.addingTimeInterval(context.tuning.suppressionWindow)
            guard let eventId = next.eventId else { return noOp(state) }
            return CrashReduction(
                state: next,
                effects: [
                    .persist,
                    .cancelBackupNotification,
                    .startStatusPolling(eventId: eventId),
                ]
            )

        case .retryableError:
            return handleRetryable(next, context: context)

        case .timeoutUnknown:
            // Row O5: retry exactly once with the same key, then fail.
            if next.timeoutRetryUsed {
                return fail(next, context: context)
            }
            next.timeoutRetryUsed = true
            return scheduleRetry(next, context: context)

        case .nonRetryableError:
            // Rows 14: immediate failure → fallback.
            return fail(next, context: context)
        }
    }

    /// Row 15/16: retryable error — retry with backoff if attempts remain and we
    /// are within the stale limit, else fail.
    private static func handleRetryable(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard let detectedAt = state.detectedAt,
              RetryPolicy.shouldRetry(
                afterAttempt: state.attemptCount,
                detectedAt: detectedAt,
                now: context.now,
                tuning: context.tuning
              )
        else {
            return fail(state, context: context)
        }
        return scheduleRetry(state, context: context)
    }

    // MARK: - retry trigger (row 19)

    private static func reduceRetryTrigger(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .queuedOffline:
            guard let detectedAt = state.detectedAt else { return noOp(state) }
            // Row 20/32: if stale, never send.
            guard RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: context.now, tuning: context.tuning)
            else {
                return toStale(state)
            }
            // Only re-dispatch when actually online; otherwise stay queued.
            guard context.online else { return noOp(state) }
            var next = state
            next.eventState = .sending
            return dispatch(next, isRetry: true, context: context, extraLeadingEffects: [])
        case .sending:
            // A scheduled backoff retry fired while in the retry wait.
            if state.requestInFlight { return noOp(state) }
            guard let detectedAt = state.detectedAt,
                  RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: context.now, tuning: context.tuning)
            else {
                return toStale(state)
            }
            return dispatch(state, isRetry: true, context: context, extraLeadingEffects: [])
        default:
            return noOp(state)
        }
    }

    // MARK: - stale limit reached (rows 20, 32)

    private static func reduceStaleLimitReached(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .queuedOffline, .sending:
            return toStale(state)
        default:
            return noOp(state)
        }
    }

    // MARK: - status poll update (row 24)

    private static func reduceStatusPollUpdate(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .sent else { return noOp(state) }
        return CrashReduction(state: state, effects: [.updateAttempts, .persist])
    }

    // MARK: - tell contacts I'm OK (row 25)

    private static func reduceTellContactsImOK(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .sent, let eventId = state.eventId else { return noOp(state) }
        return CrashReduction(state: state, effects: [.sendAllClear(eventId: eventId), .persist])
    }

    // MARK: - composer action (row 23)

    private static func reduceComposerAction(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        guard state.eventState == .fallbackPrompted else { return noOp(state) }
        // Remain resting in fallbackPrompted; persist the fallback action.
        return CrashReduction(state: state, effects: [.persist])
    }

    // MARK: - relaunch (rows 26–33)

    private static func reduceRelaunch(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        switch state.eventState {
        case .countdown:
            guard let deadline = state.deadline else { return noOp(state) }
            if context.now < deadline {
                // Row 26: resume with remaining time; re-arm timer/feedback.
                let remaining = deadline.timeIntervalSince(context.now)
                return CrashReduction(
                    state: state,
                    effects: [
                        .startCountdownFeedback(totalSeconds: remaining),
                        .scheduleBackupNotification(deadline: deadline),
                        .keepScreenAwake,
                        .presentTakeover,
                    ]
                )
            }
            // Row 27: deadline passed ⇒ prompt, never auto-send.
            var next = state
            next.eventState = .recoveryPrompted
            guard let eventId = next.eventId else { return noOp(state) }
            return CrashReduction(
                state: next,
                effects: [.presentRecoveryPrompt(eventId: eventId), .persist]
            )

        case .sending:
            // Rows 30/32: resume idempotently within the stale limit, else stale.
            guard let detectedAt = state.detectedAt,
                  RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: context.now, tuning: context.tuning)
            else {
                return toStale(state)
            }
            var next = state
            next.requestInFlight = false
            return dispatch(next, isRetry: true, context: context, extraLeadingEffects: [])

        case .queuedOffline:
            // Rows 31/32: resume retries within the stale limit, else stale.
            guard let detectedAt = state.detectedAt,
                  RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: context.now, tuning: context.tuning)
            else {
                return toStale(state)
            }
            // Resume retries: re-present the offline banner; the coordinator will
            // re-arm the retry timer / connectivity trigger.
            return CrashReduction(state: state, effects: [.presentOfflineBanner])

        default:
            // Row 33: resting/idle states are untouched by a relaunch.
            return noOp(state)
        }
    }

    // MARK: - helpers

    /// Dispatch the **initial** send (`isRetry == false`); guarded so it can
    /// happen at most once per event.
    private static func dispatchInitial(
        _ state: CrashMachineState,
        context: CrashReducerContext,
        extraLeadingEffects: [CrashEffect]
    ) -> CrashReduction {
        dispatch(state, isRetry: false, context: context, extraLeadingEffects: extraLeadingEffects)
    }

    /// Shared dispatch path. If offline, go straight to `queuedOffline` instead
    /// of emitting a send (so an offline initial send never contacts the
    /// notifier). Otherwise emit a `dispatchSend` and mark the request in flight.
    private static func dispatch(
        _ state: CrashMachineState,
        isRetry: Bool,
        context: CrashReducerContext,
        extraLeadingEffects: [CrashEffect]
    ) -> CrashReduction {
        guard let eventId = state.eventId else { return noOp(state) }

        // Offline ⇒ queue instead of dispatching (row 12 path for both initial
        // and retry dispatches).
        guard context.online else {
            var next = state
            next.eventState = .queuedOffline
            next.requestInFlight = false
            return CrashReduction(
                state: next,
                effects: extraLeadingEffects + [
                    .persist,
                    .presentOfflineBanner,
                    .presentComposerFallback,
                    .localNotSentNotice,
                    .cancelBackupNotification,
                ]
            )
        }

        var next = state
        next.eventState = .sending
        next.requestInFlight = true
        next.attemptCount += 1
        return CrashReduction(
            state: next,
            effects: extraLeadingEffects + [
                .dispatchSend(eventId: eventId, isRetry: isRetry),
                .persist,
            ]
        )
    }

    /// Schedule a backoff retry; stay in `sending` with no request in flight.
    private static func scheduleRetry(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        var next = state
        next.eventState = .sending
        next.requestInFlight = false
        let delay = RetryPolicy.delay(forAttempt: next.attemptCount, tuning: context.tuning)
        return CrashReduction(state: next, effects: [.scheduleRetry(delay: delay), .persist])
    }

    /// Transition to `failed` → offer the composer fallback (rows 14, 16).
    private static func fail(
        _ state: CrashMachineState,
        context: CrashReducerContext
    ) -> CrashReduction {
        var next = state
        next.eventState = .fallbackPrompted
        next.requestInFlight = false
        return CrashReduction(
            state: next,
            effects: [.persist, .presentComposerFallback, .localNotSentNotice]
        )
    }

    /// Transition to `stale` — never auto-send; offer composer + discard (row 20).
    private static func toStale(_ state: CrashMachineState) -> CrashReduction {
        var next = state
        next.eventState = .stale
        next.requestInFlight = false
        return CrashReduction(
            state: next,
            effects: [.persist, .presentStaleNotice, .presentComposerFallback]
        )
    }

    /// Cancel the event, start the suppression window, record the reason.
    private static func cancel(
        _ state: CrashMachineState,
        reason: CrashCancelReason,
        context: CrashReducerContext,
        fromCountdown: Bool
    ) -> CrashReduction {
        var next = state
        next.eventState = .cancelled
        next.requestInFlight = false
        next.suppressedUntil = context.now.addingTimeInterval(context.tuning.suppressionWindow)
        next.outcome = reason == .consentRevoked ? .consentRevoked : .riderCancelled
        var effects: [CrashEffect] = []
        if fromCountdown {
            effects.append(.stopCountdownFeedback)
        }
        effects.append(.cancelBackupNotification)
        effects.append(.persist)
        return CrashReduction(state: next, effects: effects)
    }

    /// An ignored/undefined transition: unchanged state, optional log effect.
    private static func noOp(
        _ state: CrashMachineState,
        log reason: CrashIgnoreReason? = nil
    ) -> CrashReduction {
        if let reason {
            return CrashReduction(state: state, effects: [.logIgnored(reason)])
        }
        return CrashReduction(state: state, effects: [])
    }
}
