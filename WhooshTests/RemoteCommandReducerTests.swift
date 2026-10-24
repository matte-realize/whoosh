import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Tests for the pure `RemoteCommandReducer` decision table (watch-companion
/// task 6, design "`RemoteCommandReducer` — decision table"; Requirements
/// 6.1–6.4, 6.10, 7.2–7.7). One `@Test` per table row (RC-1 … RC-29), plus the
/// named edge cases from tasks.md.
struct RemoteCommandReducerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let rideId = "ride-1"

    private func cmd(
        _ kind: WireCommandKind,
        id: String = "c1",
        rideId: String? = nil,
        holdConfirmed: Bool = false,
        crashEventId: String? = nil
    ) -> WireCommand {
        WireCommand(commandId: id, kind: kind, rideId: rideId,
                    holdConfirmed: holdConfirmed, crashEventId: crashEventId)
    }

    private func decide(_ input: RemoteCommandReducer.Input,
                        cache: CommandDedupeCache = CommandDedupeCache()) -> RemoteCommandReducer.Decision {
        RemoteCommandReducer.decide(input, cache: cache, now: t0)
    }

    // RC-1: dedupe cache hit replays the prior reply.
    @Test func rc1_cacheHit() {
        var cache = CommandDedupeCache()
        cache.recording("c1", reply: .init(outcome: .accepted), at: t0)
        let d = decide(.init(command: cmd(.pause, rideId: rideId),
                             activeRideId: rideId, rideState: .recording), cache: cache)
        #expect(d.fromCache)
        #expect(d.outcome == .accepted)
    }

    // RC-2: unsupported version rejected.
    @Test func rc2_unsupportedVersion() {
        let d = decide(.init(command: cmd(.pause), versionSupported: false))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .unsupportedVersion)
    }

    // RC-3: watch controls disabled rejected.
    @Test func rc3_watchDisabled() {
        let d = decide(.init(command: cmd(.pause), watchEnabled: false))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .watchDisabled)
    }

    // RC-4: stale ride id ignored.
    @Test func rc4_staleRide() {
        let d = decide(.init(command: cmd(.pause, rideId: "other"),
                             activeRideId: rideId, rideState: .recording))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .staleRide)
        #expect(d.effect == .none)
    }

    // RC-5: pause while recording/signalLost accepted.
    @Test func rc5_pauseAccepted() {
        for state in [RideState.recording, .signalLost] {
            let d = decide(.init(command: cmd(.pause, rideId: rideId),
                                 activeRideId: rideId, rideState: state))
            #expect(d.outcome == .accepted)
            #expect(d.effect == .pause)
        }
    }

    // RC-6: pause while paused is alreadyInState.
    @Test func rc6_pauseAlready() {
        let d = decide(.init(command: cmd(.pause, rideId: rideId),
                             activeRideId: rideId, rideState: .paused))
        #expect(d.outcome == .alreadyInState)
        #expect(d.effect == .none)
    }

    // RC-7: pause while idle/finished ignored noActiveRide.
    @Test func rc7_pauseNoRide() {
        for state in [RideState.idle, .finished] {
            let d = decide(.init(command: cmd(.pause), rideState: state))
            #expect(d.outcome == .ignored)
            #expect(d.reason == .noActiveRide)
        }
    }

    // RC-8: resume while paused accepted.
    @Test func rc8_resumeAccepted() {
        let d = decide(.init(command: cmd(.resume, rideId: rideId),
                             activeRideId: rideId, rideState: .paused))
        #expect(d.outcome == .accepted)
        #expect(d.effect == .resume)
    }

    // RC-9: resume while recording/signalLost alreadyInState.
    @Test func rc9_resumeAlready() {
        for state in [RideState.recording, .signalLost] {
            let d = decide(.init(command: cmd(.resume, rideId: rideId),
                                 activeRideId: rideId, rideState: state))
            #expect(d.outcome == .alreadyInState)
        }
    }

    // RC-10: resume while idle/finished ignored.
    @Test func rc10_resumeNoRide() {
        let d = decide(.init(command: cmd(.resume), rideState: .idle))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .noActiveRide)
    }

    // RC-11: stop with holdConfirmed accepted.
    @Test func rc11_stopAccepted() {
        for state in [RideState.recording, .paused, .signalLost] {
            let d = decide(.init(command: cmd(.stop, rideId: rideId, holdConfirmed: true),
                                 activeRideId: rideId, rideState: state))
            #expect(d.outcome == .accepted)
            #expect(d.effect == .stop)
        }
    }

    // RC-12: stop without hold rejected holdRequired.
    @Test func rc12_stopHoldRequired() {
        let d = decide(.init(command: cmd(.stop, rideId: rideId, holdConfirmed: false),
                             activeRideId: rideId, rideState: .recording))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .holdRequired)
        #expect(d.effect == .none)
    }

    // RC-13: stop while finished alreadyInState.
    @Test func rc13_stopFinished() {
        let d = decide(.init(command: cmd(.stop, holdConfirmed: true), rideState: .finished))
        #expect(d.outcome == .alreadyInState)
    }

    // RC-14: stop while idle ignored.
    @Test func rc14_stopIdle() {
        let d = decide(.init(command: cmd(.stop, holdConfirmed: true), rideState: .idle))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .noActiveRide)
    }

    // RC-15: saveClip while recording accepted (saved or pending).
    @Test func rc15_saveClipAccepted() {
        let saved = decide(.init(command: cmd(.saveClip, rideId: rideId),
                                 activeRideId: rideId, rideState: .recording,
                                 camera: .init(isRecording: true),
                                 clipSavedImmediately: true))
        #expect(saved.outcome == .accepted)
        #expect(saved.detail == .saved)
        #expect(saved.effect == .saveClip)

        let pending = decide(.init(command: cmd(.saveClip, rideId: rideId),
                                   activeRideId: rideId, rideState: .recording,
                                   camera: .init(isRecording: true),
                                   clipSavedImmediately: false))
        #expect(pending.detail == .pending)
    }

    // RC-16: saveClip within debounce ignored debounced.
    @Test func rc16_saveClipDebounced() {
        let d = decide(.init(command: cmd(.saveClip, rideId: rideId),
                             activeRideId: rideId, rideState: .recording,
                             camera: .init(isRecording: true, debounced: true)))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .debounced)
        #expect(d.effect == .none)
    }

    // RC-17: saveClip while camera not recording rejected cameraNotRecording.
    @Test func rc17_saveClipCameraOff() {
        let d = decide(.init(command: cmd(.saveClip, rideId: rideId),
                             activeRideId: rideId, rideState: .recording,
                             camera: .init(isRecording: false)))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .cameraNotRecording)
        #expect(d.detail == .cameraOff)
    }

    // RC-18: saveClip with storage full rejected storageFull.
    @Test func rc18_saveClipStorageFull() {
        let d = decide(.init(command: cmd(.saveClip, rideId: rideId),
                             activeRideId: rideId, rideState: .recording,
                             camera: .init(isRecording: true, storageFull: true)))
        #expect(d.outcome == .rejected)
        #expect(d.detail == .storageFull)
    }

    // RC-19: saveClip with no active ride ignored.
    @Test func rc19_saveClipNoRide() {
        let d = decide(.init(command: cmd(.saveClip), rideState: .idle))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .noActiveRide)
    }

    // RC-20: cancel during countdown accepted (cancelled or tooLate).
    @Test func rc20_cancelCountdown() {
        let won = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "e1"),
                               activeRideId: rideId, rideState: .recording,
                               crash: .init(phase: .countdown, eventId: "e1"),
                               crashCancelWon: true))
        #expect(won.outcome == .accepted)
        #expect(won.detail == .cancelled)
        #expect(won.effect == .cancelCrashCountdown)

        // Cancel loses the tie to expiry → tooLate (tasks.md edge case).
        let late = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "e1"),
                                activeRideId: rideId, rideState: .recording,
                                crash: .init(phase: .countdown, eventId: "e1"),
                                crashCancelWon: false))
        #expect(late.outcome == .accepted)
        #expect(late.detail == .tooLate)
    }

    // RC-21: cancel while queuedOffline accepted cancelled.
    @Test func rc21_cancelQueued() {
        let d = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "e1"),
                             activeRideId: rideId, rideState: .recording,
                             crash: .init(phase: .queuedOffline, eventId: "e1")))
        #expect(d.outcome == .accepted)
        #expect(d.detail == .cancelled)
        #expect(d.effect == .cancelCrashCountdown)
    }

    // RC-22: cancel while a request is in flight rejected notCancellable.
    @Test func rc22_cancelInFlight() {
        let d = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "e1"),
                             activeRideId: rideId, rideState: .recording,
                             crash: .init(phase: .sending, eventId: "e1")))
        #expect(d.outcome == .rejected)
        #expect(d.detail == .notCancellable)
        #expect(d.effect == .none)
    }

    // RC-23: cancel when already sent/cancelled alreadyInState tooLate.
    @Test func rc23_cancelResolved() {
        for phase in [WireCrashPhase.sent, .cancelled, .stale] {
            let d = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "e1"),
                                 activeRideId: rideId, rideState: .recording,
                                 crash: .init(phase: phase, eventId: "e1")))
            #expect(d.outcome == .alreadyInState)
            #expect(d.detail == .tooLate)
        }
    }

    // RC-24: cancel with no countdown or a different id ignored.
    @Test func rc24_cancelNoCountdown() {
        let none = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId),
                                activeRideId: rideId, rideState: .recording,
                                crash: .none))
        #expect(none.outcome == .ignored)
        #expect(none.reason == .noCountdown)

        let wrongId = decide(.init(command: cmd(.cancelCrashCountdown, rideId: rideId, crashEventId: "other"),
                                   activeRideId: rideId, rideState: .recording,
                                   crash: .init(phase: .countdown, eventId: "e1")))
        #expect(wrongId.outcome == .ignored)
        #expect(wrongId.reason == .staleEvent)
    }

    // RC-25: requestStart armed + idle + guards accepted with new ride id.
    @Test func rc25_requestStartAccepted() {
        let d = decide(.init(command: cmd(.requestStart, id: "start-1", rideId: "new-ride"),
                             activeRideId: nil, rideState: .idle,
                             arming: .armedReady))
        #expect(d.outcome == .accepted)
        #expect(d.detail == .started)
        #expect(d.newRideId == "new-ride")
        #expect(d.effect == .startFromWatch(newRideId: "new-ride"))
    }

    // RC-26: requestStart while not armed rejected notArmed.
    @Test func rc26_requestStartNotArmed() {
        let d = decide(.init(command: cmd(.requestStart), rideState: .idle, arming: .notArmed))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .notArmed)
    }

    // RC-27: requestStart with a failing guard rejected notReady.
    @Test func rc27_requestStartNotReady() {
        let d = decide(.init(command: cmd(.requestStart), rideState: .idle,
                             arming: .armedNotReady([.camera])))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .notReady)
    }

    // RC-28: requestStart while a ride is active rejected rideActive.
    @Test func rc28_requestStartRideActive() {
        let d = decide(.init(command: cmd(.requestStart), activeRideId: rideId,
                             rideState: .recording, arming: .armedReady))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .rideActive)
    }

    // RC-29: unknown command rejected unknownCommand.
    @Test func rc29_unknownCommand() {
        let d = decide(.init(command: cmd(.unknown)))
        #expect(d.outcome == .rejected)
        #expect(d.reason == .unknownCommand)
    }

    // Edge case (tasks.md): a stale ride id can never stop a new ride.
    @Test func staleIdNeverStopsNewRide() {
        let d = decide(.init(command: cmd(.stop, rideId: "old-ride", holdConfirmed: true),
                             activeRideId: "new-ride", rideState: .recording))
        #expect(d.outcome == .ignored)
        #expect(d.reason == .staleRide)
        #expect(d.effect == .none)
    }

    // Edge case (tasks.md): a duplicate id returns the cached reply, not a re-run.
    @Test func duplicateIdReturnsCachedReply() {
        var cache = CommandDedupeCache()
        let input = RemoteCommandReducer.Input(
            command: cmd(.stop, rideId: rideId, holdConfirmed: true),
            activeRideId: rideId, rideState: .recording)
        let first = RemoteCommandReducer.decide(input, cache: cache, now: t0)
        #expect(first.outcome == .accepted)
        #expect(first.effect == .stop)
        // Caller records the reply, then a duplicate arrives.
        cache.recording("c1", reply: .init(outcome: first.outcome, reason: first.reason,
                                            detail: first.detail, newRideId: first.newRideId),
                        at: t0)
        let dup = RemoteCommandReducer.decide(input, cache: cache, now: t0.addingTimeInterval(2))
        #expect(dup.fromCache)
        #expect(dup.effect == .none) // no second stop
    }
}
