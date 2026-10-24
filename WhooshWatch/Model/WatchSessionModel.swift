import Foundation
import Observation
import WhooshWire

/// The watch app's single `@Observable` session model (watch-companion design
/// "Watch-side design → Structure"; tasks 15, 20). It is deliberately **thin and
/// phone-authoritative**: it owns the `WireLink`, the codec, the pure reducers
/// (`WatchRideReducer`, `WatchCommandTracker`, `CrashCountdownModel`,
/// `WatchNoticeLog`), the `HapticPlaying`, `WorkoutSessionController`, and a
/// `MonotonicClock` — all behind protocols with fakes. It records no ride,
/// holds no ride data, and decides no state transition; it reflects what the
/// phone published, sends typed commands, and plays haptics.
///
/// **Privacy:** this model imports no connectivity, Health, or watch-haptic
/// framework — those live only in their confined files (`Services/Link/`,
/// `Services/Workout/`, `Services/Haptics/`), reached through the seams.
/// Enforced by `scripts/privacy-check.sh`.
///
/// Honest copy: the rear-vehicle cue is experimental; Whoosh cannot guarantee
/// detection or delivery.
@Observable
@MainActor
public final class WatchSessionModel {
    // MARK: Seams (injected; fakes in previews/tests)

    @ObservationIgnored private let link: WireLink
    @ObservationIgnored private let haptics: HapticPlaying
    @ObservationIgnored private let workout: WorkoutSessionController
    @ObservationIgnored private let clock: MonotonicClock
    @ObservationIgnored private let tuning: WatchTuning
    @ObservationIgnored private let selector = HapticPatternSelector()

    // MARK: Pure state (not observed directly; projected into `view`)

    @ObservationIgnored private var reducer: WatchRideReducer
    @ObservationIgnored private var commandTracker: WatchCommandTracker
    @ObservationIgnored private var countdown = CrashCountdownModel()
    @ObservationIgnored private var limiter: WristHapticLimiter
    @ObservationIgnored private var noticeLog: WatchNoticeLog
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var lastRearCueMs: Int?
    @ObservationIgnored private var negotiatedVersion = WireVersion.current
    @ObservationIgnored private var currentRideId: String?

    // MARK: Observed, view-facing state

    /// The latest projected ride view model (numbers, chips, controls).
    public private(set) var view: WatchRideReducer.ViewModel
    /// The crash countdown phase/seconds snapshot, if a countdown is active.
    public private(set) var countdownPhase: CrashCountdownModel.Phase = .hidden
    public private(set) var countdownSeconds: Int = 0
    public private(set) var countdownIsDrill = false
    public private(set) var countdownContactCount = 0
    /// The last end-of-ride summary received, if any (Summary page).
    public private(set) var summary: WireSummary?
    /// Notices for this ride (newest last) and the unread badge count.
    public private(set) var notices: [WatchNoticeLog.Entry] = []
    public private(set) var unreadNoticeCount = 0
    /// Per-command UI state keyed by command kind (pending / confirmed / failed).
    public private(set) var commandStates: [WireCommandKind: WatchCommandTracker.Status] = [:]
    /// Whether the link is currently reachable.
    public private(set) var reachable = false
    /// Diagnostics: cues played, commands sent (counts only; privacy).
    public private(set) var cuesPlayed = 0
    public private(set) var commandsSent = 0

    // MARK: Settings (watch UserDefaults mirror; defaults here)

    /// Default Save-to-Health choice when the 60 s timer elapses.
    public var defaultSaveToHealth = true
    /// Mirror of the phone's "Also play a sound" setting.
    public var alsoPlaySound = false
    /// Watch haptics enabled (false → limiter suppresses).
    public var hapticsEnabled = true {
        didSet { limiter.disabled = !hapticsEnabled }
    }

    // MARK: Init

    public init(
        link: WireLink,
        haptics: HapticPlaying,
        workout: WorkoutSessionController,
        clock: MonotonicClock = UptimeMonotonicClock(),
        tuning: WatchTuning = WatchTuning()
    ) {
        self.link = link
        self.haptics = haptics
        self.workout = workout
        self.clock = clock
        self.tuning = tuning
        self.reducer = WatchRideReducer(tuning: tuning)
        self.commandTracker = WatchCommandTracker(tuning: tuning)
        self.limiter = WristHapticLimiter(tuning: tuning)
        self.noticeLog = WatchNoticeLog(capacity: tuning.noticeLogSize)
        self.view = WatchRideReducer(tuning: tuning).viewModel(nowMs: 0)
    }

    // MARK: Lifecycle

    /// Activate the link and wire up its callbacks, then send `hello`.
    public func start() async {
        await link.onLiveMessage { [weak self] env in
            // The link hands off to the main actor; the handler is synchronous,
            // so hop via a detached task for the async model work and return nil
            // (the reply, when needed, is sent separately). For the loopback/
            // fake path this is sufficient for previews and smoke tests.
            guard let self else { return nil }
            Task { @MainActor in self.receive(env) }
            return nil
        }
        await link.onContext { [weak self] env in
            guard let self else { return }
            Task { @MainActor in self.receive(env) }
        }
        await link.onQueued { [weak self] env in
            guard let self else { return }
            Task { @MainActor in self.receive(env) }
        }
        await link.onReachabilityChange { [weak self] value in
            guard let self else { return }
            Task { @MainActor in self.setReachable(value) }
        }
        workout.onWatchStateChange { [weak self] state in
            guard let self else { return }
            Task { @MainActor in await self.reportWatchState(state) }
        }
        await link.activate()
        await sendHello()
        reachable = await link.isReachable
        refreshView()
    }

    // MARK: Inbound

    /// Decode and route an inbound envelope to the right handler.
    public func receive(_ env: WireEnvelope) {
        switch env.t {
        case .hello:
            if let hello = try? WireCodec.decodePayload(WireHello.self, from: env) {
                applyHello(hello)
            }
        case .status:
            if let status = try? WireCodec.decodePayload(WireRideStatus.self, from: env) {
                apply(status: status)
            }
        case .alert:
            if let alert = try? WireCodec.decodePayload(WireAlert.self, from: env) {
                Task { await handle(alert: alert, replyingTo: env.id) }
            }
        case .reply:
            if let reply = try? WireCodec.decodePayload(WireCommandReply.self, from: env) {
                apply(reply: reply)
            }
        case .summary:
            if let s = try? WireCodec.decodePayload(WireSummary.self, from: env) {
                summary = s
            }
        case .command, .watchState, .receipt, .unknown:
            break   // the watch does not receive these
        }
    }

    private func applyHello(_ hello: WireHello) {
        let local = WireVersion.minSupported...WireVersion.current
        if let v = WireVersion.negotiate(local: local, remote: hello.versionRange) {
            negotiatedVersion = v
        }
    }

    private func apply(status: WireRideStatus) {
        let now = clock.nowMs
        // A new ride clears the per-ride notice log (privacy: current ride only).
        if currentRideId != nil && currentRideId != status.rideId {
            noticeLog.reset()
            refreshNotices()
        }
        currentRideId = status.rideId
        let accepted = reducer.apply(status, nowMs: now)
        // Keep the demo gate on the limiter in sync with the phone's demo flag.
        limiter.demoActive = status.demo
        // Crash sub-object → countdown model.
        if let crash = status.crash {
            countdown.apply(crash, nowMs: now)
        } else if countdown.phase != .hidden && !countdown.isActive {
            countdown.clear()
        }
        if accepted { refreshView() }
        // A finished ride ends the keep-alive; an active ride starts it.
        switch status.state {
        case .recording, .signalLost:
            workout.rideBecameActive()
        case .paused:
            workout.ridePaused()
        case .finished:
            workout.rideFinished()
        default:
            break
        }
        refreshView()
    }

    private func apply(reply: WireCommandReply) {
        if let effect = commandTracker.reply(commandId: reply.commandId) {
            applyCommandEffect(effect)
        }
        // A cancel reply carries the concrete crash detail.
        if let detail = reply.detail, countdown.isActive || reply.detail == .cancelled {
            countdown.applyCancelReply(detail: detail)
        }
        // Reconcile from the embedded fresh status.
        apply(status: reply.status)
        refreshView()
    }

    private func setReachable(_ value: Bool) {
        reachable = value
        reducer.setLink(value ? .connected : .lost)
        if !value {
            for e in commandTracker.linkLost() { applyCommandEffect(e) }
        }
        refreshView()
    }

    // MARK: Alerts

    private func handle(alert: WireAlert, replyingTo messageId: String) async {
        let now = clock.nowMs
        // Freshness + limiter decide whether to buzz.
        let outcome = limiter.admit(alert, nowMs: now, playerActive: haptics.isActive)
        var playedAfterMs: Int? = nil
        if outcome.result == .played {
            if outcome.preempted { haptics.cancel() }
            let ctx = HapticPatternSelector.Context(
                msSinceLastRearCue: lastRearCueMs.map { now - $0 }
            )
            let pattern = selector.pattern(for: alert, context: ctx)
            haptics.play(pattern)
            playedAfterMs = 0
            cuesPlayed += 1
            if alert.kind == .rearVehicleCaution { lastRearCueMs = now }
        }
        // Log the notice (replay logs without buzzing / unread).
        noticeLog.record(alert, timeIntoRideMs: reducer.elapsedMs(nowMs: now))
        refreshNotices()
        // Send a receipt back as a reply to the alert's message id.
        let receipt = WireAlertReceipt(
            alertId: alert.alertId,
            result: outcome.result,
            workoutActive: workout.watchState.session == .running,
            playedAfterMs: playedAfterMs
        )
        await sendReceipt(receipt)
    }

    // MARK: Outbound commands (rider intents from the UI)

    public func pause() { issue(kind: .pause) }
    public func resume() { issue(kind: .resume) }
    public func saveClip() { issue(kind: .saveClip) }
    public func stop() { issue(kind: .stop, holdConfirmed: true) }
    public func requestStart() { issue(kind: .requestStart, holdConfirmed: true) }

    /// The rider tapped Cancel on the crash countdown.
    public func cancelCountdown() {
        let id = UUID().uuidString
        countdown.cancel(commandId: id)
        countdownPhase = countdown.phase
        let effect = commandTracker.tap(
            commandId: id,
            kind: .cancelCrashCountdown,
            nowMs: clock.nowMs,
            isCrashCancel: true
        )
        applyCommandEffect(effect)
    }

    private func issue(kind: WireCommandKind, holdConfirmed: Bool = false) {
        let id = UUID().uuidString
        let effect = commandTracker.tap(commandId: id, kind: kind, nowMs: clock.nowMs)
        if case .send = effect {
            pendingHoldConfirmed[id] = holdConfirmed
        }
        applyCommandEffect(effect)
    }

    @ObservationIgnored private var pendingHoldConfirmed: [String: Bool] = [:]

    private func applyCommandEffect(_ effect: WatchCommandTracker.Effect) {
        switch effect {
        case let .send(commandId, kind, attempt, queueCopy):
            Task { await sendCommand(commandId: commandId, kind: kind, attempt: attempt, queueCopy: queueCopy) }
            commandStates[kind] = .pending
        case let .confirmed(_, kind):
            commandStates[kind] = .confirmed
        case let .notConfirmed(_, kind):
            commandStates[kind] = .notConfirmed
            // A failed command buzzes a short "not confirmed".
            if haptics.isActive { haptics.play(HapticPatternSelector.commandNotConfirmedPattern) }
        case .rejectedLocally:
            break
        }
        refreshView()
    }

    // MARK: Encoding + send helpers

    private func nextSeq() -> Int { seq += 1; return seq }

    private func sendHello() async {
        let hello = WireHello(
            minVersion: WireVersion.minSupported,
            maxVersion: WireVersion.current,
            appBuild: appBuild,
            sessionNonce: UUID().uuidString,
            capabilities: ["startFromWatch", "crashCancel", "haptics.v1"]
        )
        guard let env = try? WireCodec.encode(hello, id: UUID().uuidString, seq: nextSeq(),
                                               sentAt: Date().timeIntervalSince1970,
                                               version: negotiatedVersion) else { return }
        _ = await link.send(env)
    }

    private func sendCommand(commandId: String, kind: WireCommandKind, attempt: Int, queueCopy: Bool) async {
        let hold = pendingHoldConfirmed[commandId] ?? false
        let command = WireCommand(
            commandId: commandId,
            kind: kind,
            rideId: currentRideId,
            holdConfirmed: hold,
            crashEventId: kind == .cancelCrashCountdown ? countdown.eventId : nil,
            issuedAgoMs: 0,
            attempt: attempt
        )
        guard let env = try? WireCodec.encode(command, id: commandId, seq: nextSeq(),
                                              sentAt: Date().timeIntervalSince1970,
                                              version: negotiatedVersion) else { return }
        commandsSent += 1
        let result: WireSendResult
        if queueCopy {
            result = await link.send(env)
            _ = await link.transfer(env)
        } else {
            result = await link.send(env)
        }
        // A synchronous reply (fake/loopback path) reconciles immediately.
        if case let .delivered(reply?) = result { receive(reply) }
    }

    private func sendReceipt(_ receipt: WireAlertReceipt) async {
        guard let env = try? WireCodec.encode(receipt, id: UUID().uuidString, seq: nextSeq(),
                                              sentAt: Date().timeIntervalSince1970,
                                              version: negotiatedVersion) else { return }
        _ = await link.send(env)
    }

    private func reportWatchState(_ state: WireWatchState) async {
        guard let env = try? WireCodec.encode(state, id: UUID().uuidString, seq: nextSeq(),
                                              sentAt: Date().timeIntervalSince1970,
                                              version: negotiatedVersion) else { return }
        _ = await link.updateContext(env)
    }

    // MARK: Tick (called ~1 Hz by the UI to project time + run retries)

    /// Advance time-driven state: retry/TTL timers, elapsed projection, stale
    /// display, and the crash countdown schedule. The UI calls this ~1 Hz.
    public func tick() {
        let now = clock.nowMs
        for e in commandTracker.tick(nowMs: now) { applyCommandEffect(e) }
        // Crash countdown haptic schedule.
        if countdown.isActive, countdown.hapticDue(nowMs: now), haptics.isActive {
            haptics.play(HapticPatternSelector.crashCountdownStartPattern)
            cuesPlayed += 1
        }
        refreshView()
    }

    // MARK: Projection

    private func refreshView() {
        let now = clock.nowMs
        view = reducer.viewModel(nowMs: now)
        countdownPhase = countdown.phase
        countdownSeconds = countdown.displayedSeconds(nowMs: now)
        countdownIsDrill = countdown.isDrill
        countdownContactCount = countdown.contactCount
    }

    private func refreshNotices() {
        notices = noticeLog.entries
        unreadNoticeCount = noticeLog.unreadCount
    }

    /// The rider opened the Notices page.
    public func markNoticesRead() {
        noticeLog.markAllRead()
        refreshNotices()
    }

    // MARK: Health choice (Summary page)

    public func saveWorkout() { workout.saveWorkout() }
    public func discardWorkout() { workout.discardWorkout() }

    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    // MARK: Preview / demo injection (no link required)

    /// Apply a scripted status (and optional summary) directly, as if it had
    /// arrived from the phone. Used by SwiftUI previews and demo mode so every
    /// page can be shown before the real link is live.
    public func injectForPreview(status: WireRideStatus, summary: WireSummary? = nil) {
        apply(status: status)
        if let summary { self.summary = summary }
        refreshView()
        refreshNotices()
    }

    /// Apply only a crash sub-object (for the countdown takeover preview).
    public func injectForPreview(crashOnly crash: WireCrashStatus) {
        countdown.apply(crash, nowMs: clock.nowMs)
        refreshView()
    }

    /// Record a scripted alert directly (demo "feel the patterns" / notices).
    public func injectForPreview(alert: WireAlert) {
        Task { await handle(alert: alert, replyingTo: UUID().uuidString) }
    }
}
