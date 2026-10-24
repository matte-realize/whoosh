import Foundation

/// The pure camera recording reducer: `(state, event, context) → (state,
/// [effects])` implementing **every row** of the design's transition table
/// (rear-camera spec Requirement 5.9, 11.2, 11.3, 12.1–12.3, 17.1, 17.2, 19.2;
/// design "Camera recording state machine", rows 1–24).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). It performs
/// no I/O, reads no clock, and generates no ids; everything it needs comes in
/// via `CameraReducerContext`. Effects are returned as **data** for the
/// coordinator to execute.
///
/// Invariants (defense in depth, asserted by the tests):
/// - **No effect ever touches GPS.** A camera state change never affects ride
///   recording (property check `noEffectTouchesGPS` is trivially true because the
///   effect enum has no GPS case; the test also drives random event sequences).
/// - **A session is only started while permission is `authorized`** — the only
///   `startSession` emitters (rows 1, 15–17) require `rideActive` and reachable
///   states that are themselves gated by the authorized start. Row 1 guards on
///   `permission.canStartCapture`; the resume rows re-enter `preparing`, which
///   re-checks the start guard before re-starting.
/// - **Undefined transitions are no-ops** (row 24), never crashes.
enum CameraStateMachine {
    /// Reduce one event. Returns the next state and ordered effects.
    static func reduce(
        _ state: CameraRecordingState,
        _ event: CameraReducerEvent,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        switch event {
        // Row 21 and 23 apply from (almost) any state, so handle them first.
        case .rideEndedOrFeatureDisabled:
            return reduceRideEnded(state)
        case .ridePausedOrResumed:
            // Row 23: the camera keeps recording through a pause/resume.
            return .init(state: state)
        case .permissionRevoked:
            return reducePermissionRevoked(state)
        case .rideStarted:
            return reduceRideStarted(state, context)
        case .sessionRunning:
            return reduceSessionRunning(state, context)
        case .startFailure:
            return reduceStartFailure(state, context)
        case .thermalStepDown:
            return reduceThermalStepDown(state, context)
        case .thermalStepUp:
            return reduceThermalStepUp(state, context)
        case let .interrupted(reason):
            return reduceInterrupted(state, reason)
        case .interruptionEnded:
            return reduceInterruptionEnded(state, context)
        case .thermalCriticalStop:
            return reduceStop(state, reason: .thermal)
        case .storageStop:
            return reduceStop(state, reason: .storage)
        case .batteryStop:
            return reduceStop(state, reason: .battery)
        case .resumeConditionCleared:
            return reduceResume(state, context)
        case .writerFailed:
            return reduceWriterFailed(state, context)
        case .retryTimer:
            return reduceRetryTimer(state, context)
        }
    }

    // MARK: - Rows 1–3: ride started from `off`

    private static func reduceRideStarted(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard state == .off else { return noOp(state) }

        // Row 2: permission not authorized.
        guard context.permission.canStartCapture else {
            return .init(state: .off, effects: [.alert(.notStartedPermission), .publishStatus])
        }
        // Row 3: storage below the start minimum (or no resolvable profile).
        guard context.storageMeetsStartMinimum else {
            return .init(state: .off, effects: [.alert(.notStartedStorage), .publishStatus])
        }
        guard let profile = context.resolvedProfile else {
            // No profile the device can satisfy — treat like "cannot start"; the
            // ride still runs (handled by the coordinator as unavailable).
            return .init(state: .off, effects: [.alert(.stopped(.failed)), .publishStatus])
        }
        // Row 1: start.
        return .init(state: .preparing, effects: [.startSession(profile), .publishStatus])
    }

    // MARK: - Row 4: session running

    private static func reduceSessionRunning(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard state == .preparing else { return noOp(state) }
        // The coordinator resolved and started this profile (carried in the
        // context), so we record at exactly that profile.
        let profile = context.resolvedProfile ?? .standard
        return .init(state: .recording(profile), effects: [.publishStatus, .schedulePolling])
    }

    // MARK: - Rows 5–6: start failure while preparing

    private static func reduceStartFailure(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard state == .preparing else { return noOp(state) }
        // Row 5: attempts remaining (design: attempts < 2) ⇒ retry.
        if context.startAttempts < 2 {
            return .init(
                state: .preparing,
                effects: [.scheduleRetry(after: context.tuning.writerRestartDelay)]
            )
        }
        // Row 6: exhausted ⇒ failed.
        return .init(
            state: .failed(.startTimeout),
            effects: [.alert(.stopped(.failed)), .publishStatus]
        )
    }

    // MARK: - Row 7: thermal step down

    private static func reduceThermalStepDown(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        switch state {
        case let .recording(profile), let .degraded(profile, _):
            let next = context.steppedProfile ?? profile
            return .init(
                state: .degraded(next, .thermal),
                effects: [.applyProfileStep(next), .alert(.reduced), .publishStatus]
            )
        default:
            return noOp(state)
        }
    }

    // MARK: - Row 8: thermal step up

    private static func reduceThermalStepUp(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard case let .degraded(profile, _) = state else { return noOp(state) }
        guard context.stepUpHysteresisSatisfied else { return noOp(state) }
        let next = context.steppedProfile ?? profile
        // Stepping back to the full requested profile returns to `recording`;
        // a higher-but-still-reduced profile stays `degraded`.
        if next == context.resolvedProfile {
            return .init(
                state: .recording(next),
                effects: [.applyProfileStep(next), .publishStatus]
            )
        }
        return .init(
            state: .degraded(next, .thermal),
            effects: [.applyProfileStep(next), .publishStatus]
        )
    }

    // MARK: - Row 9: interruption

    private static func reduceInterrupted(
        _ state: CameraRecordingState,
        _ reason: InterruptionReasonKind
    ) -> CameraReduction {
        switch state {
        case .recording, .degraded:
            return .init(
                state: .interrupted(reason),
                effects: [.finalizeSegment, .alert(.interrupted), .publishStatus]
            )
        default:
            return noOp(state)
        }
    }

    // MARK: - Rows 10–11: interruption ended

    private static func reduceInterruptionEnded(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard case .interrupted = state else { return noOp(state) }
        if context.rideActive {
            // Row 10: resume in a new segment with a discontinuity flag.
            return .init(
                state: .preparing,
                effects: [.openNewSegmentWithDiscontinuity, .alert(.resumed), .publishStatus]
            )
        }
        // Row 11: ride no longer active ⇒ teardown.
        return .init(state: .off, effects: [.teardownSession, .publishStatus])
    }

    // MARK: - Rows 12–14, 18: policy / permission stops

    private static func reduceStop(
        _ state: CameraRecordingState,
        reason: CameraStopReason
    ) -> CameraReduction {
        switch state {
        case .recording, .degraded:
            return .init(
                state: .stopped(reason),
                effects: [.finalizeSegment, .alert(.stopped(reason)), .publishStatus]
            )
        default:
            return noOp(state)
        }
    }

    private static func reducePermissionRevoked(_ state: CameraRecordingState) -> CameraReduction {
        // Row 18: from any camera-active state.
        switch state {
        case .recording, .degraded, .preparing, .interrupted:
            return .init(
                state: .stopped(.permission),
                effects: [.finalizeSegment, .alert(.stopped(.permission)), .publishStatus]
            )
        default:
            return noOp(state)
        }
    }

    // MARK: - Rows 15–17: resume after a policy stop

    private static func reduceResume(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard case .stopped(let reason) = state else { return noOp(state) }
        // Only thermal/storage/battery stops auto-resume (rows 15–17); a
        // permission or ride-ended stop does not.
        switch reason {
        case .thermal, .storage, .battery:
            break
        case .permission, .failed, .rideEnded:
            return noOp(state)
        }
        guard context.rideActive else { return noOp(state) }
        // Never restart capture without camera permission (it may have been
        // revoked while recording was stopped for heat, storage or battery).
        guard context.permission.canStartCapture else { return noOp(state) }
        guard let profile = context.resolvedProfile else { return noOp(state) }
        return .init(state: .preparing, effects: [.startSession(profile), .publishStatus])
    }

    // MARK: - Rows 19–20: writer failure

    private static func reduceWriterFailed(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        switch state {
        case .recording, .degraded:
            if context.writerRestartTried {
                // Row 20: restart already tried ⇒ failed.
                return .init(
                    state: .failed(.writer),
                    effects: [.alert(.stopped(.failed)), .publishStatus]
                )
            }
            // Row 19: discard the bad segment and restart once.
            return .init(
                state: .preparing,
                effects: [
                    .discardSegment,
                    .scheduleRetry(after: context.tuning.writerRestartDelay),
                ]
            )
        default:
            return noOp(state)
        }
    }

    // MARK: - Row 21: ride ended / feature disabled

    private static func reduceRideEnded(_ state: CameraRecordingState) -> CameraReduction {
        // From any state: finalize, finish pending pins, delete unpinned
        // segments, tear down. Already-off is a no-op (row 24 spirit).
        guard state != .off else { return noOp(state) }
        return .init(
            state: .off,
            effects: [
                .finalizeSegment,
                .finishPendingPins,
                .deleteUnpinnedSegments,
                .teardownSession,
                .publishStatus,
            ]
        )
    }

    // MARK: - Row 22: retry from `failed`

    private static func reduceRetryTimer(
        _ state: CameraRecordingState,
        _ context: CameraReducerContext
    ) -> CameraReduction {
        guard case .failed = state else { return noOp(state) }
        guard context.rideActive, context.failedRetryCount < 3 else { return noOp(state) }
        guard context.permission.canStartCapture else { return noOp(state) }
        guard let profile = context.resolvedProfile else { return noOp(state) }
        return .init(state: .preparing, effects: [.startSession(profile), .publishStatus])
    }

    // MARK: - Row 24: undefined transition is a no-op

    private static func noOp(_ state: CameraRecordingState) -> CameraReduction {
        .init(state: state)
    }
}
