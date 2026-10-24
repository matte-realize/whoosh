import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure camera recording reducer (rear-camera spec task 7, design
/// "Camera recording state machine"): one named test per table row CM-1…24, plus
/// two property checks (no event ever starts a session while the permission is
/// not `authorized`; no effect ever touches GPS).
struct CameraStateMachineTests {
    private static let tuning = RideCameraTuning()

    /// A context that would allow a clean start (authorized, storage ok, profile
    /// resolved, ride active), overridable per test.
    private func ctx(
        permission: CameraPermissionStatus = .authorized,
        storage: Bool = true,
        profile: CaptureProfile? = .standard,
        rideActive: Bool = true,
        startAttempts: Int = 0,
        writerRestartTried: Bool = false,
        failedRetryCount: Int = 0,
        stepUp: Bool = false,
        stepped: CaptureProfile? = nil
    ) -> CameraReducerContext {
        CameraReducerContext(
            permission: permission,
            storageMeetsStartMinimum: storage,
            resolvedProfile: profile,
            rideActive: rideActive,
            startAttempts: startAttempts,
            writerRestartTried: writerRestartTried,
            failedRetryCount: failedRetryCount,
            stepUpHysteresisSatisfied: stepUp,
            steppedProfile: stepped
        )
    }

    // MARK: - Rows 1–3: ride started

    /// CM-1: off + rideStarted (authorized, storage, profile) ⇒ preparing; starts session.
    @Test func cm1_startWhenReady() {
        let r = CameraStateMachine.reduce(.off, .rideStarted, ctx())
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.startSession(.standard)))
    }

    /// CM-2: off + rideStarted, permission not authorized ⇒ off; permission alert.
    @Test func cm2_startBlockedByPermission() {
        let r = CameraStateMachine.reduce(.off, .rideStarted, ctx(permission: .denied))
        #expect(r.state == .off)
        #expect(r.effects.contains(.alert(.notStartedPermission)))
        #expect(r.effects.contains(where: { if case .startSession = $0 { return true }; return false }) == false)
    }

    /// CM-3: off + rideStarted, storage below start min ⇒ off; storage alert.
    @Test func cm3_startBlockedByStorage() {
        let r = CameraStateMachine.reduce(.off, .rideStarted, ctx(storage: false))
        #expect(r.state == .off)
        #expect(r.effects.contains(.alert(.notStartedStorage)))
    }

    // MARK: - Row 4: session running

    /// CM-4: preparing + sessionRunning ⇒ recording(profile); publishes + polls.
    @Test func cm4_sessionRunning() {
        let r = CameraStateMachine.reduce(.preparing, .sessionRunning, ctx(profile: .efficient))
        #expect(r.state == .recording(.efficient))
        #expect(r.effects.contains(.schedulePolling))
    }

    // MARK: - Rows 5–6: start failure

    /// CM-5: preparing + startFailure, attempts < 2 ⇒ preparing; schedules retry.
    @Test func cm5_startRetry() {
        let r = CameraStateMachine.reduce(.preparing, .startFailure, ctx(startAttempts: 1))
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.scheduleRetry(after: Self.tuning.writerRestartDelay)))
    }

    /// CM-6: preparing + startFailure, attempts exhausted ⇒ failed(startTimeout).
    @Test func cm6_startExhausted() {
        let r = CameraStateMachine.reduce(.preparing, .startFailure, ctx(startAttempts: 2))
        #expect(r.state == .failed(.startTimeout))
        #expect(r.effects.contains(.alert(.stopped(.failed))))
    }

    // MARK: - Row 7: thermal step down

    /// CM-7: recording + thermalStepDown ⇒ degraded; applies the stepped profile.
    @Test func cm7_thermalStepDown() {
        let r = CameraStateMachine.reduce(
            .recording(.standard),
            .thermalStepDown,
            ctx(stepped: .reduced)
        )
        #expect(r.state == .degraded(.reduced, .thermal))
        #expect(r.effects.contains(.applyProfileStep(.reduced)))
        #expect(r.effects.contains(.alert(.reduced)))
    }

    // MARK: - Row 8: thermal step up

    /// CM-8: degraded + thermalStepUp (hysteresis satisfied, back to requested)
    /// ⇒ recording.
    @Test func cm8_thermalStepUp() {
        let r = CameraStateMachine.reduce(
            .degraded(.reduced, .thermal),
            .thermalStepUp,
            ctx(profile: .standard, stepUp: true, stepped: .standard)
        )
        #expect(r.state == .recording(.standard))
        #expect(r.effects.contains(.applyProfileStep(.standard)))

        // Hysteresis NOT satisfied ⇒ no-op.
        let hold = CameraStateMachine.reduce(
            .degraded(.reduced, .thermal),
            .thermalStepUp,
            ctx(stepUp: false, stepped: .standard)
        )
        #expect(hold.state == .degraded(.reduced, .thermal))
    }

    // MARK: - Row 9: interruption

    /// CM-9: recording + interrupted ⇒ interrupted(reason); finalizes + notice.
    @Test func cm9_interrupted() {
        let r = CameraStateMachine.reduce(.recording(.standard), .interrupted(.background), ctx())
        #expect(r.state == .interrupted(.background))
        #expect(r.effects.contains(.finalizeSegment))
        #expect(r.effects.contains(.alert(.interrupted)))
    }

    // MARK: - Rows 10–11: interruption ended

    /// CM-10: interrupted + interruptionEnded, ride active ⇒ preparing with a
    /// new discontinuous segment.
    @Test func cm10_interruptionEndedResumes() {
        let r = CameraStateMachine.reduce(.interrupted(.background), .interruptionEnded, ctx(rideActive: true))
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.openNewSegmentWithDiscontinuity))
        #expect(r.effects.contains(.alert(.resumed)))
    }

    /// CM-11: interrupted + interruptionEnded, ride not active ⇒ off; teardown.
    @Test func cm11_interruptionEndedTeardown() {
        let r = CameraStateMachine.reduce(.interrupted(.background), .interruptionEnded, ctx(rideActive: false))
        #expect(r.state == .off)
        #expect(r.effects.contains(.teardownSession))
    }

    // MARK: - Row 12: thermal critical stop

    /// CM-12: recording + thermalCriticalStop ⇒ stopped(thermal); finalize + alert.
    @Test func cm12_thermalCriticalStop() {
        let r = CameraStateMachine.reduce(.recording(.standard), .thermalCriticalStop, ctx())
        #expect(r.state == .stopped(.thermal))
        #expect(r.effects.contains(.finalizeSegment))
        #expect(r.effects.contains(.alert(.stopped(.thermal))))
    }

    // MARK: - Row 13: storage stop

    /// CM-13: degraded + storageStop ⇒ stopped(storage).
    @Test func cm13_storageStop() {
        let r = CameraStateMachine.reduce(.degraded(.reduced, .thermal), .storageStop, ctx())
        #expect(r.state == .stopped(.storage))
        #expect(r.effects.contains(.alert(.stopped(.storage))))
    }

    // MARK: - Row 14: battery stop

    /// CM-14: recording + batteryStop ⇒ stopped(battery).
    @Test func cm14_batteryStop() {
        let r = CameraStateMachine.reduce(.recording(.standard), .batteryStop, ctx())
        #expect(r.state == .stopped(.battery))
        #expect(r.effects.contains(.alert(.stopped(.battery))))
    }

    // MARK: - Rows 15–17: resume after a policy stop

    /// CM-15: stopped(thermal) + resumeConditionCleared, ride active ⇒ preparing.
    @Test func cm15_resumeAfterThermal() {
        let r = CameraStateMachine.reduce(.stopped(.thermal), .resumeConditionCleared, ctx(profile: .reduced))
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.startSession(.reduced)))
    }

    /// CM-16: stopped(storage) + resumeConditionCleared ⇒ preparing.
    @Test func cm16_resumeAfterStorage() {
        let r = CameraStateMachine.reduce(.stopped(.storage), .resumeConditionCleared, ctx())
        #expect(r.state == .preparing)
    }

    /// CM-17: stopped(battery) + resumeConditionCleared ⇒ preparing; but a
    /// permission stop never auto-resumes.
    @Test func cm17_resumeAfterBatteryNotPermission() {
        let battery = CameraStateMachine.reduce(.stopped(.battery), .resumeConditionCleared, ctx())
        #expect(battery.state == .preparing)

        let permission = CameraStateMachine.reduce(.stopped(.permission), .resumeConditionCleared, ctx())
        #expect(permission.state == .stopped(.permission)) // no-op
    }

    // MARK: - Row 18: permission revoked

    /// CM-18: recording + permissionRevoked ⇒ stopped(permission); finalize + alert.
    @Test func cm18_permissionRevoked() {
        let r = CameraStateMachine.reduce(.recording(.standard), .permissionRevoked, ctx())
        #expect(r.state == .stopped(.permission))
        #expect(r.effects.contains(.finalizeSegment))
        #expect(r.effects.contains(.alert(.stopped(.permission))))
    }

    // MARK: - Rows 19–20: writer failure

    /// CM-19: recording + writerFailed, restart not tried ⇒ preparing; discards
    /// the bad segment and restarts once.
    @Test func cm19_writerFailedRestart() {
        let r = CameraStateMachine.reduce(.recording(.standard), .writerFailed, ctx(writerRestartTried: false))
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.discardSegment))
        #expect(r.effects.contains(.scheduleRetry(after: Self.tuning.writerRestartDelay)))
    }

    /// CM-20: recording + writerFailed, restart already tried ⇒ failed(writer).
    @Test func cm20_writerFailedTerminal() {
        let r = CameraStateMachine.reduce(.recording(.standard), .writerFailed, ctx(writerRestartTried: true))
        #expect(r.state == .failed(.writer))
        #expect(r.effects.contains(.alert(.stopped(.failed))))
    }

    // MARK: - Row 21: ride ended / feature disabled

    /// CM-21: any active state + rideEndedOrFeatureDisabled ⇒ off; full teardown.
    @Test func cm21_rideEndedTeardown() {
        let r = CameraStateMachine.reduce(.recording(.standard), .rideEndedOrFeatureDisabled, ctx())
        #expect(r.state == .off)
        #expect(r.effects.contains(.finalizeSegment))
        #expect(r.effects.contains(.finishPendingPins))
        #expect(r.effects.contains(.deleteUnpinnedSegments))
        #expect(r.effects.contains(.teardownSession))

        // Already off ⇒ no-op, no effects.
        let offNoop = CameraStateMachine.reduce(.off, .rideEndedOrFeatureDisabled, ctx())
        #expect(offNoop.state == .off)
        #expect(offNoop.effects.isEmpty)
    }

    // MARK: - Row 22: retry from failed

    /// CM-22: failed + retryTimer, ride active and under the cap ⇒ preparing;
    /// past the cap it is a no-op.
    @Test func cm22_failedRetry() {
        let r = CameraStateMachine.reduce(.failed(.writer), .retryTimer, ctx(failedRetryCount: 2))
        #expect(r.state == .preparing)
        #expect(r.effects.contains(.startSession(.standard)))

        let capped = CameraStateMachine.reduce(.failed(.writer), .retryTimer, ctx(failedRetryCount: 3))
        #expect(capped.state == .failed(.writer)) // no-op at the cap
    }

    // MARK: - Row 23: pause/resume keeps recording

    /// CM-23: recording + ridePausedOrResumed ⇒ same state, no effects
    /// (recordWhilePaused is on by default).
    @Test func cm23_pauseKeepsRecording() {
        let r = CameraStateMachine.reduce(.recording(.standard), .ridePausedOrResumed, ctx())
        #expect(r.state == .recording(.standard))
        #expect(r.effects.isEmpty)
    }

    // MARK: - Row 24: undefined transition is a no-op

    /// CM-24: an event with no defined transition from the current state is a
    /// no-op (e.g. sessionRunning while off, thermalStepUp while recording).
    @Test func cm24_undefinedIsNoOp() {
        let a = CameraStateMachine.reduce(.off, .sessionRunning, ctx())
        #expect(a.state == .off)
        #expect(a.effects.isEmpty)

        let b = CameraStateMachine.reduce(.recording(.standard), .thermalStepUp, ctx(stepUp: true, stepped: .standard))
        #expect(b.state == .recording(.standard)) // step up only valid from degraded
        #expect(b.effects.isEmpty)

        let c = CameraStateMachine.reduce(.off, .interruptionEnded, ctx())
        #expect(c.state == .off)
        #expect(c.effects.isEmpty)
    }

    // MARK: - Property checks

    /// Property: no event sequence ever emits `startSession` while the permission
    /// is not `authorized`. We drive every event from every reachable state with
    /// a denied permission and assert no `startSession` effect appears.
    @Test func property_noStartWhileUnauthorized() {
        let states: [CameraRecordingState] = [
            .off, .preparing, .recording(.standard), .degraded(.reduced, .thermal),
            .interrupted(.background), .stopped(.thermal), .stopped(.storage),
            .stopped(.battery), .stopped(.permission), .stopping, .failed(.writer),
        ]
        let events: [CameraReducerEvent] = [
            .rideStarted, .sessionRunning, .startFailure, .thermalStepDown, .thermalStepUp,
            .interrupted(.background), .interruptionEnded, .thermalCriticalStop, .storageStop,
            .batteryStop, .resumeConditionCleared, .permissionRevoked, .writerFailed,
            .rideEndedOrFeatureDisabled, .retryTimer, .ridePausedOrResumed,
        ]
        let deniedCtx = ctx(permission: .denied)
        for s in states {
            for e in events {
                let r = CameraStateMachine.reduce(s, e, deniedCtx)
                for effect in r.effects {
                    if case .startSession = effect {
                        Issue.record("startSession emitted while unauthorized: state=\(s) event=\(e)")
                    }
                }
            }
        }
    }

    /// Property: the effect set has no GPS/location member, so no reduction can
    /// ever touch ride location. (Structural guarantee; verified by exhaustively
    /// driving events and confirming every effect is one of the known
    /// camera-only cases.)
    @Test func property_noEffectTouchesGPS() {
        let states: [CameraRecordingState] = [
            .off, .preparing, .recording(.standard), .degraded(.reduced, .thermal),
            .interrupted(.background), .stopped(.thermal), .failed(.writer),
        ]
        let events: [CameraReducerEvent] = [
            .rideStarted, .sessionRunning, .startFailure, .thermalStepDown, .thermalStepUp,
            .interrupted(.background), .interruptionEnded, .thermalCriticalStop, .storageStop,
            .batteryStop, .resumeConditionCleared, .permissionRevoked, .writerFailed,
            .rideEndedOrFeatureDisabled, .retryTimer, .ridePausedOrResumed,
        ]
        for s in states {
            for e in events {
                let r = CameraStateMachine.reduce(s, e, ctx())
                for effect in r.effects {
                    #expect(isCameraOnlyEffect(effect))
                }
            }
        }
    }

    /// Every `CameraEffect` case is camera/recording-only (never GPS). This
    /// switch is exhaustive, so adding a GPS effect would fail to compile here.
    private func isCameraOnlyEffect(_ effect: CameraEffect) -> Bool {
        switch effect {
        case .startSession, .applyProfileStep, .finalizeSegment,
             .openNewSegmentWithDiscontinuity, .discardSegment, .teardownSession,
             .finishPendingPins, .deleteUnpinnedSegments, .scheduleRetry,
             .schedulePolling, .publishStatus, .alert:
            return true
        }
    }
}
