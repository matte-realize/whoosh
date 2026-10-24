import Testing
import Foundation
@testable import WhooshWire

/// Task 11 — watch-side reducers.
/// WR (ride reducer), WC-1…6 (command tracker), CT-1…8 (countdown),
/// WS-1…19 (workout session machine), plus the notice log.
@Suite("Watch-side reducers")
struct WatchReducerTests {

    // MARK: - Helpers

    private func status(
        rideId: String = "r1",
        epoch: Int = 1,
        seq: Int = 1,
        state: WireRideState = .recording,
        activeMs: Int = 0,
        distance10m: Int = 0,
        speedDms: Int? = nil,
        camera: WireCameraState = .recording,
        banner: WireBanner = .none,
        start: WireStartState = .ready,
        crash: WireCrashStatus? = nil
    ) -> WireRideStatus {
        WireRideStatus(
            rideId: rideId, epoch: epoch, seq: seq, state: state,
            activeMs: activeMs, distance10m: distance10m, speedDms: speedDms,
            camera: WireCameraStatus(feature: .on, state: camera),
            phone: WirePhoneState(batteryPct: 80, charging: false), banner: banner, crash: crash, start: start
        )
    }

    // MARK: - WR: ride reducer

    @Test("WR-1: a first status is accepted; an older seq in the same epoch is ignored")
    func wr1_seqGate() {
        var r = WatchRideReducer()
        #expect(r.apply(status(seq: 5), nowMs: 0) == true)
        #expect(r.apply(status(seq: 4), nowMs: 100) == false)   // older
        #expect(r.apply(status(seq: 5), nowMs: 100) == false)   // duplicate
        #expect(r.apply(status(seq: 6), nowMs: 100) == true)    // newer
    }

    @Test("WR-2: a new epoch resets the seq gate")
    func wr2_epochReset() {
        var r = WatchRideReducer()
        #expect(r.apply(status(epoch: 1, seq: 9), nowMs: 0) == true)
        // Lower seq but new epoch → accepted.
        #expect(r.apply(status(epoch: 2, seq: 1), nowMs: 10) == true)
    }

    @Test("WR-3: elapsed advances while recording and freezes while paused")
    func wr3_elapsedProjection() {
        var r = WatchRideReducer()
        r.apply(status(state: .recording, activeMs: 10_000), nowMs: 1_000)
        #expect(r.elapsedMs(nowMs: 4_000) == 13_000)   // +3 s of watch time
        r.apply(status(seq: 2, state: .paused, activeMs: 13_000), nowMs: 4_000)
        #expect(r.elapsedMs(nowMs: 9_000) == 13_000)   // frozen
    }

    @Test("WR-4: the display goes stale after statusStaleMs without a message")
    func wr4_staleness() {
        var r = WatchRideReducer()
        r.apply(status(state: .recording), nowMs: 0)
        #expect(r.isStale(nowMs: 14_000) == false)
        #expect(r.isStale(nowMs: 15_000) == true)
        #expect(r.viewModel(nowMs: 15_000).phase == .activeStale)
        #expect(r.viewModel(nowMs: 15_000).showStaleChip == true)
    }

    @Test("WR-5: control enablement reflects ride state, camera, and link")
    func wr5_controls() {
        var r = WatchRideReducer()
        // Recording with camera on → pause/stop/save all enabled.
        r.apply(status(state: .recording, camera: .recording), nowMs: 0)
        var vm = r.viewModel(nowMs: 0)
        #expect(vm.controls.pauseResumeEnabled)
        #expect(vm.controls.stopEnabled)
        #expect(vm.controls.saveClipEnabled)

        // Camera off → save clip disabled with reason.
        r.apply(status(seq: 2, state: .recording, camera: .off), nowMs: 1_000)
        vm = r.viewModel(nowMs: 1_000)
        #expect(vm.controls.saveClip == .notRecording)
        #expect(!vm.controls.saveClipEnabled)

        // Link lost → everything disabled with linkDown.
        r.setLink(.lost)
        vm = r.viewModel(nowMs: 1_000)
        #expect(vm.controls.pauseResume == .linkDown)
        #expect(vm.phase == .noLink)
    }

    @Test("WR-6: start is enabled only when the status is armed and idle")
    func wr6_startArming() {
        var r = WatchRideReducer()
        r.apply(status(state: .idle, start: .ready), nowMs: 0)
        #expect(r.viewModel(nowMs: 0).controls.start == .notArmed)
        r.apply(status(seq: 2, state: .idle, start: .armed(untilMs: 300_000)), nowMs: 1_000)
        #expect(r.viewModel(nowMs: 1_000).controls.startEnabled)
    }

    // MARK: - WC: command tracker

    @Test("WC-1: a tap becomes pending and asks the caller to send attempt 1")
    func wc1_tapSends() {
        var t = WatchCommandTracker()
        let e = t.tap(commandId: "c1", kind: .pause, nowMs: 0)
        #expect(e == .send(commandId: "c1", kind: .pause, attempt: 1, queueCopy: false))
        #expect(t.hasPending)
    }

    @Test("WC-2: taps within the 500 ms spacing are rejected locally")
    func wc2_spacing() {
        var t = WatchCommandTracker()
        _ = t.tap(commandId: "c1", kind: .pause, nowMs: 0)
        let e = t.tap(commandId: "c2", kind: .resume, nowMs: 300)
        #expect(e == .rejectedLocally(kind: .resume))
    }

    @Test("WC-3: a second command of the same kind while one is pending is rejected")
    func wc3_alreadyPending() {
        var t = WatchCommandTracker()
        _ = t.tap(commandId: "c1", kind: .saveClip, nowMs: 0)
        let e = t.tap(commandId: "c2", kind: .saveClip, nowMs: 1_000)
        #expect(e == .rejectedLocally(kind: .saveClip))
    }

    @Test("WC-4: retries reuse the same id at 2.5 s and 5 s, then TTL → not confirmed")
    func wc4_retriesAndTtl() {
        var t = WatchCommandTracker()
        _ = t.tap(commandId: "c1", kind: .stop, nowMs: 0)
        // Before 2.5 s: no resend.
        #expect(t.tick(nowMs: 1_000).isEmpty)
        // At 2.5 s: attempt 2, same id.
        #expect(t.tick(nowMs: 2_500) == [.send(commandId: "c1", kind: .stop, attempt: 2, queueCopy: false)])
        // At 5 s: attempt 3.
        #expect(t.tick(nowMs: 5_000) == [.send(commandId: "c1", kind: .stop, attempt: 3, queueCopy: false)])
        // At TTL (8 s): not confirmed.
        #expect(t.tick(nowMs: 8_000) == [.notConfirmed(commandId: "c1", kind: .stop)])
        #expect(!t.hasPending)
    }

    @Test("WC-5: a reply confirms and clears the pending command")
    func wc5_reply() {
        var t = WatchCommandTracker()
        _ = t.tap(commandId: "c1", kind: .pause, nowMs: 0)
        #expect(t.reply(commandId: "c1") == .confirmed(commandId: "c1", kind: .pause))
        #expect(!t.hasPending)
        // A reply for an unknown id is a no-op.
        #expect(t.reply(commandId: "nope") == nil)
    }

    @Test("WC-6: link loss fails pending commands immediately; crash cancel retries every 1 s with a queue copy")
    func wc6_linkLossAndCrashException() {
        var t = WatchCommandTracker()
        _ = t.tap(commandId: "c1", kind: .pause, nowMs: 0)
        let lost = t.linkLost()
        #expect(lost == [.notConfirmed(commandId: "c1", kind: .pause)])
        #expect(!t.hasPending)

        // Crash cancel retries every 1 s with queueCopy true.
        var t2 = WatchCommandTracker()
        _ = t2.tap(commandId: "x1", kind: .cancelCrashCountdown, nowMs: 0, isCrashCancel: true)
        #expect(t2.tick(nowMs: 500).isEmpty)
        #expect(t2.tick(nowMs: 1_000) == [.send(commandId: "x1", kind: .cancelCrashCountdown, attempt: 2, queueCopy: true)])
        #expect(t2.tick(nowMs: 2_000) == [.send(commandId: "x1", kind: .cancelCrashCountdown, attempt: 3, queueCopy: true)])
    }

    // MARK: - CT: countdown model

    private func crash(
        remainingMs: Int,
        phase: WireCrashPhase = .countdown,
        isDrill: Bool = false,
        eventId: String = "e1"
    ) -> WireCrashStatus {
        WireCrashStatus(eventId: eventId, remainingMs: remainingMs, isDrill: isDrill,
                        contactCount: 2, phase: phase)
    }

    @Test("CT-1: remaining projects from relative time and never goes negative")
    func ct1_remaining() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 30_000), nowMs: 1_000)
        #expect(m.remainingMs(nowMs: 6_000) == 25_000)
        #expect(m.remainingMs(nowMs: 40_000) == 0)
        #expect(m.displayedSeconds(nowMs: 6_000) == 25)
    }

    @Test("CT-2: the model shows countdown and carries the drill flag and contact count")
    func ct2_drill() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 20_000, isDrill: true), nowMs: 0)
        #expect(m.phase == .countdown)
        #expect(m.isDrill)
        #expect(m.contactCount == 2)
        #expect(m.isActive)
    }

    @Test("CT-3: the announcement schedule fires at start, every 10 s, and the last 5 s")
    func ct3_announcements() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 30_000), nowMs: 0)
        #expect(m.announcementDue(nowMs: 0) == 30)       // start
        #expect(m.announcementDue(nowMs: 0) == nil)      // same second, no repeat
        #expect(m.announcementDue(nowMs: 10_000) == 20)  // 20 s left (mult of 10)
        #expect(m.announcementDue(nowMs: 11_000) == nil) // 19 s, not due
        #expect(m.announcementDue(nowMs: 26_000) == 4)   // last 5 s
        #expect(m.announcementDue(nowMs: 27_000) == 3)   // each of the last 5 s
    }

    @Test("CT-4: the haptic schedule is every 3 s, then every 1.5 s in the last 10 s, capped at 20")
    func ct4_hapticSchedule() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 30_000), nowMs: 0)
        #expect(m.hapticDue(nowMs: 0) == true)      // first fires immediately
        #expect(m.hapticDue(nowMs: 1_000) == false) // < 3 s since last
        #expect(m.hapticDue(nowMs: 3_000) == true)  // every 3 s outside the last 10 s
        #expect(m.hapticDue(nowMs: 4_500) == false) // 1.5 s not enough outside last 10 s

        // In the last 10 s the interval tightens to 1.5 s.
        var m2 = CrashCountdownModel()
        m2.apply(crash(remainingMs: 9_000), nowMs: 0)
        #expect(m2.hapticDue(nowMs: 0) == true)     // first
        #expect(m2.hapticDue(nowMs: 1_000) == false)
        #expect(m2.hapticDue(nowMs: 1_500) == true) // 1.5 s cadence in the last 10 s
    }

    @Test("CT-5: cancelling moves through cancelling → cancelled / tooLate / failed by reply")
    func ct5_cancelOutcomes() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 20_000), nowMs: 0)
        m.cancel(commandId: "cmd1")
        if case .cancelling(let id) = m.phase { #expect(id == "cmd1") } else { Issue.record("not cancelling") }
        m.applyCancelReply(detail: .cancelled)
        #expect(m.phase == .cancelled)

        var m2 = CrashCountdownModel()
        m2.apply(crash(remainingMs: 1_000), nowMs: 0)
        m2.cancel(commandId: "cmd2")
        m2.applyCancelReply(detail: .tooLate)
        #expect(m2.phase == .tooLate)
    }

    @Test("CT-6: a status phase of sending/sent/cancelled is reflected")
    func ct6_statusPhases() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 0, phase: .sending), nowMs: 0)
        #expect(m.phase == .sending)
        m.apply(crash(remainingMs: 0, phase: .sent), nowMs: 1_000)
        #expect(m.phase == .sent)
    }

    @Test("CT-7: clear hides the countdown and resets the schedule")
    func ct7_clear() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 20_000), nowMs: 0)
        m.clear()
        #expect(m.phase == .hidden)
        #expect(!m.isActive)
        #expect(m.eventId == nil)
    }

    @Test("CT-8: a local cancelling state survives a repeated countdown status")
    func ct8_cancellingSurvivesStatus() {
        var m = CrashCountdownModel()
        m.apply(crash(remainingMs: 20_000), nowMs: 0)
        m.cancel(commandId: "cmd")
        // Another countdown status arrives before the reply.
        m.apply(crash(remainingMs: 18_000), nowMs: 2_000)
        if case .cancelling = m.phase {} else { Issue.record("cancelling lost") }
    }

    // MARK: - Notice log

    @Test("Notice log keeps the last N, counts unread, and a replay logs read")
    func noticeLog() {
        var log = WatchNoticeLog(capacity: 3)
        for i in 0..<5 {
            let a = WireAlert(alertId: "n\(i)", kind: .cameraInterrupted, tier: .notice,
                              createdAgoMs: 0, ttlMs: 60_000)
            log.record(a, timeIntoRideMs: i * 1_000)
        }
        #expect(log.entries.count == 3)              // capped
        #expect(log.entries.first?.alertId == "n2")  // oldest dropped
        #expect(log.unreadCount == 3)

        let replay = WireAlert(alertId: "rp", kind: .clipSaved, tier: .confirm,
                               createdAgoMs: 0, ttlMs: 60_000, replay: true)
        log.record(replay, timeIntoRideMs: 9_000)
        #expect(log.entries.last?.unread == false)   // replay logged read
        log.markAllRead()
        #expect(log.unreadCount == 0)
        log.reset()
        #expect(log.entries.isEmpty)
    }

    // MARK: - WS: workout session machine (19 rows)

    @Test("WS-1: off + ride active (auth unknown) → authorizing, requests authorization")
    func ws1() {
        var m = WorkoutSessionStateMachine()
        let o = m.apply(.rideBecameActive(authorized: nil))
        #expect(o.state == .authorizing)
        #expect(o.effects.contains(.requestAuthorization))
    }

    @Test("WS-2: off + ride active (authorized) → preparing, creates the session")
    func ws2() {
        var m = WorkoutSessionStateMachine()
        let o = m.apply(.rideBecameActive(authorized: true))
        #expect(o.state == .preparing)
        #expect(o.effects.contains(.createAndStartSession))
    }

    @Test("WS-3: authorizing + granted → preparing")
    func ws3() {
        var m = WorkoutSessionStateMachine(state: .authorizing)
        #expect(m.apply(.authorizationGranted).state == .preparing)
    }

    @Test("WS-4: authorizing + denied → unavailable(healthDenied)")
    func ws4() {
        var m = WorkoutSessionStateMachine(state: .authorizing)
        #expect(m.apply(.authorizationDenied).state == .unavailable(.healthDenied))
    }

    @Test("WS-5: preparing + session running → running, arms haptics")
    func ws5() {
        var m = WorkoutSessionStateMachine(state: .preparing)
        let o = m.apply(.sessionRunning)
        #expect(o.state == .running)
        #expect(o.effects.contains(.armHaptics))
    }

    @Test("WS-6: preparing + error/timeout → failed(startFailed)")
    func ws6() {
        var m = WorkoutSessionStateMachine(state: .preparing)
        #expect(m.apply(.startError).state == .failed(.startFailed))
        var m2 = WorkoutSessionStateMachine(state: .preparing)
        #expect(m2.apply(.startTimeout).state == .failed(.startFailed))
    }

    @Test("WS-7: running + ride paused → paused")
    func ws7() {
        var m = WorkoutSessionStateMachine(state: .running)
        #expect(m.apply(.ridePaused).state == .paused)
    }

    @Test("WS-8: paused + ride recording → running")
    func ws8() {
        var m = WorkoutSessionStateMachine(state: .paused)
        #expect(m.apply(.rideRecording).state == .running)
    }

    @Test("WS-9: running/paused + ride finished → stopping")
    func ws9() {
        var m = WorkoutSessionStateMachine(state: .running)
        let o = m.apply(.rideFinished)
        #expect(o.state == .stopping)
        #expect(o.effects.contains(.startHealthChoiceTimer))
        var m2 = WorkoutSessionStateMachine(state: .paused)
        #expect(m2.apply(.rideFinished).state == .stopping)
    }

    @Test("WS-10: stopping + save → ended(saved)")
    func ws10() {
        var m = WorkoutSessionStateMachine(state: .stopping)
        let o = m.apply(.saveChosen)
        #expect(o.state == .ended(.saved))
        #expect(o.effects.contains(.endCollectionAndSave))
    }

    @Test("WS-11: stopping + discard → ended(discarded)")
    func ws11() {
        var m = WorkoutSessionStateMachine(state: .stopping)
        let o = m.apply(.discardChosen)
        #expect(o.state == .ended(.discarded))
        #expect(o.effects.contains(.discardCollection))
    }

    @Test("WS-12: running + another workout started → failed(anotherWorkout)")
    func ws12() {
        var m = WorkoutSessionStateMachine(state: .running)
        #expect(m.apply(.anotherWorkoutStarted).state == .failed(.anotherWorkout))
    }

    @Test("WS-13: failed(startFailed) + retry while active and tries<2 → preparing")
    func ws13() {
        var m = WorkoutSessionStateMachine(state: .failed(.startFailed))
        #expect(m.apply(.retryTimer(rideActive: true, tries: 1)).state == .preparing)
        // tries exhausted → stays failed.
        var m2 = WorkoutSessionStateMachine(state: .failed(.startFailed))
        #expect(m2.apply(.retryTimer(rideActive: true, tries: 2)).state == .failed(.startFailed))
    }

    @Test("WS-14: running + system ended → failed(systemEnded)")
    func ws14() {
        var m = WorkoutSessionStateMachine(state: .running)
        #expect(m.apply(.systemEndedSession).state == .failed(.systemEnded))
    }

    @Test("WS-15: running + orphan timeout → stopping with a notice")
    func ws15() {
        var m = WorkoutSessionStateMachine(state: .running)
        let o = m.apply(.orphanTimeout)
        #expect(o.state == .stopping)
        #expect(o.effects.contains(.emitNotice(.orphanTimeout)))
    }

    @Test("WS-16: running + low battery → stopping with a notice")
    func ws16() {
        var m = WorkoutSessionStateMachine(state: .running)
        let o = m.apply(.lowBattery)
        #expect(o.state == .stopping)
        #expect(o.effects.contains(.emitNotice(.lowBattery)))
    }

    @Test("WS-17: off + relaunch finds a recoverable session → preparing, recovers")
    func ws17() {
        var m = WorkoutSessionStateMachine(state: .off)
        let o = m.apply(.relaunchFoundRecoverableSession)
        #expect(o.state == .preparing)
        #expect(o.effects.contains(.recoverActiveSession))
    }

    @Test("WS-18: ended + next ride / summary dismissed → off, resets")
    func ws18() {
        var m = WorkoutSessionStateMachine(state: .ended(.saved))
        let o = m.apply(.nextRideOrSummaryDismissed)
        #expect(o.state == .off)
        #expect(o.effects.contains(.reset))
    }

    @Test("WS-19: an undefined (state, event) pair is a no-op")
    func ws19() {
        var m = WorkoutSessionStateMachine(state: .running)
        // Granting authorization while already running is undefined → no change.
        #expect(m.apply(.authorizationGranted).state == .running)
    }
}
