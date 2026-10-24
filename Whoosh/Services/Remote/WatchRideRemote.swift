import Foundation
import WhooshWire

/// The phone-side `RideRemoteControlling` that speaks the wire contract over a
/// `WireLink` (watch-companion spec task 13; design "Eyes-free surfaces" +
/// "Channels and the wire contract"; Requirement 6, 7, 20.8). It bridges the
/// Foundation-only wire package to the app's existing remote seam.
///
/// ## Publishing (phone → watch)
/// `publish(_:)` maps the rear-camera `RideStatus` to the allowlisted
/// `WireRideStatus` with `WireMapper`, asks the pure `StatusTransportPolicy`
/// whether to send live and/or write context, encodes with `WireCodec`, and
/// sends over the `WireLink`. The L3 time rule means the watch ticks its own
/// clock; no per-second message is sent.
///
/// ## Commands (watch → phone)
/// `handleCommand(_:)` decodes a `command` envelope, runs it through the
/// `CommandDedupeCache` (a retried `commandId` replays the identical reply) and
/// the pure `RemoteCommandReducer` (the authoritative guard between the wrist
/// and the ride engine), applies an accepted `Effect` through the injected
/// bridge (`onCommand`), and returns a `WireCommandReply` embedding a **fresh**
/// status so the watch reconciles from the reply. A remote failure never changes
/// ride state or GPS (the reducer and bridge call only existing idempotent
/// intents).
///
/// The ride engine is **not** modified: state is read through the injected
/// `snapshot` provider and effects are applied through `onCommand`.
///
/// ## Isolation
/// `@MainActor` (project default isolation): the mapper, reducer, cache, and the
/// bridge run on the main actor. The real WatchConnectivity adapter (task 16)
/// receives a message on its delegate queue, hops to the main actor, calls
/// `handleCommand`, and returns the reply through its `replyHandler`; the
/// loopback integration tests call `handleCommand` on the main actor directly.
@MainActor
final class WatchRideRemote: RideRemoteControlling {

    /// Everything the reducer and mapper need for one command/publish, read from
    /// the ride engine without mutating it.
    struct Snapshot: Sendable {
        var status: RideStatus
        var rideId: String
        var epoch: Int
        var clipCount: Int
        var isDemo: Bool
        var watchEnabled: Bool
        var camera: RemoteCommandReducer.CameraSnapshot
        var crash: RemoteCommandReducer.CrashSnapshot
        var arming: RemoteCommandReducer.ArmingSnapshot
        var armedUntilMs: Int?
        var versionSupported: Bool
        var clipSavedImmediately: Bool
        var crashCancelWon: Bool

        init(
            status: RideStatus,
            rideId: String = "",
            epoch: Int = 0,
            clipCount: Int = 0,
            isDemo: Bool = false,
            watchEnabled: Bool = true,
            camera: RemoteCommandReducer.CameraSnapshot = .off,
            crash: RemoteCommandReducer.CrashSnapshot = .none,
            arming: RemoteCommandReducer.ArmingSnapshot = .notArmed,
            armedUntilMs: Int? = nil,
            versionSupported: Bool = true,
            clipSavedImmediately: Bool = true,
            crashCancelWon: Bool = true
        ) {
            self.status = status
            self.rideId = rideId
            self.epoch = epoch
            self.clipCount = clipCount
            self.isDemo = isDemo
            self.watchEnabled = watchEnabled
            self.camera = camera
            self.crash = crash
            self.arming = arming
            self.armedUntilMs = armedUntilMs
            self.versionSupported = versionSupported
            self.clipSavedImmediately = clipSavedImmediately
            self.crashCancelWon = crashCancelWon
        }
    }

    // MARK: Dependencies

    private let link: WireLink
    private let clock: Clock
    private let mapper = WireMapper()
    private let transport: StatusTransportPolicy
    private let snapshot: @MainActor () -> Snapshot

    // MARK: State

    private var seq = 0
    private var lastEpoch = 0
    private var lastContextAt: Date?
    private var dedupe: CommandDedupeCache
    private var reachableFlag = false

    /// `RideRemoteControlling.onCommand` — set to the `RideRemoteBridge` by the
    /// composition root; invoked for an accepted effect.
    var onCommand: ((RideRemoteCommand, @escaping (RideRemoteCommandReply) -> Void) -> Void)?

    var isReachable: Bool { reachableFlag }

    init(
        link: WireLink,
        clock: Clock,
        tuning: WatchTuning = WatchTuning(),
        snapshot: @escaping @MainActor () -> Snapshot
    ) {
        self.link = link
        self.clock = clock
        self.transport = StatusTransportPolicy(tuning: tuning)
        self.snapshot = snapshot
        self.dedupe = CommandDedupeCache(tuning: tuning)
    }

    /// Activate the link and track reachability, and register the live handler
    /// so a wrist `command` reaches `handleCommand` on the main actor and its
    /// reply is sent back over the same link. The live callback is `@Sendable`
    /// and may run off the main actor, so it schedules the handling and returns
    /// `nil` synchronously; the watch's dedupe cache replays the same id if it
    /// retries before the async reply lands.
    func activate() async {
        await link.onReachabilityChange { [weak self] reachable in
            Task { @MainActor in self?.reachableFlag = reachable }
        }
        await link.onLiveMessage { [weak self] envelope in
            guard let self else { return nil }
            Task { @MainActor in self.handleAndReply(envelope) }
            return nil
        }
        await link.activate()
        reachableFlag = await link.isReachable
    }

    /// Handle a command and send its reply over the link (main-actor).
    private func handleAndReply(_ envelope: WireEnvelope) {
        guard let reply = handleCommand(envelope) else { return }
        let link = self.link
        Task { _ = await link.send(reply) }
    }

    // MARK: - Publishing

    func publish(_ status: RideStatus) {
        publish(status, trigger: .stateChange)
    }

    /// Publish with an explicit transport trigger (heartbeat, refresh, crash
    /// phase change). Encodes and sends per the `StatusTransportPolicy`.
    func publish(_ status: RideStatus, trigger: StatusTransportPolicy.Trigger) {
        let now = clock.now()
        let snap = snapshot()

        if snap.epoch != lastEpoch {
            lastEpoch = snap.epoch
            seq = 0
        }

        var wire = mapper.map(
            status, rideId: snap.rideId, epoch: snap.epoch, seq: seq,
            clipCount: snap.clipCount, demo: snap.isDemo,
            watchEnabled: snap.watchEnabled, now: now
        )
        wire.crash = crashStatus(from: snap)
        wire.start = startState(from: snap)

        let msSinceContext = lastContextAt.map { Int(now.timeIntervalSince($0) * 1000) } ?? Int.max
        let decision = transport.decide(
            linkState: reachableFlag ? .ready(peer: Self.readyPeer) : .installedUnreachable,
            displayActive: true,
            trigger: trigger,
            msSinceLastContext: msSinceContext
        )
        guard decision.live || decision.context else { return }

        let currentSeq = seq
        guard let envelope = try? WireCodec.encode(
            wire, id: wire.rideId.isEmpty ? UUID().uuidString : "\(wire.rideId).\(currentSeq)",
            seq: currentSeq, sentAt: now.timeIntervalSince1970
        ) else { return }
        seq += 1

        let link = self.link
        if decision.live { Task { _ = await link.send(envelope) } }
        if decision.context {
            lastContextAt = now
            Task { _ = await link.updateContext(envelope) }
        }
    }

    // MARK: - Command handling

    /// Process a live `command` envelope and return the encoded reply envelope
    /// (or `nil` when the envelope is not a decodable command). Applies the
    /// accepted side effect through the bridge.
    @discardableResult
    func handleCommand(_ envelope: WireEnvelope) -> WireEnvelope? {
        guard let command = try? WireCodec.decodePayload(WireCommand.self, from: envelope) else {
            return nil
        }
        let now = clock.now()
        let snap = snapshot()

        // Dedupe: a retried commandId replays the identical reply fields and
        // never re-applies the effect.
        if let cached = dedupe.cachedReply(for: command.commandId, at: now) {
            return encodeReply(
                commandId: command.commandId, outcome: cached.outcome, reason: cached.reason,
                detail: cached.detail, newRideId: cached.newRideId, snap: snap, now: now
            )
        }

        let input = RemoteCommandReducer.Input(
            command: command,
            activeRideId: snap.rideId.isEmpty ? nil : snap.rideId,
            rideState: snap.status.rideState,
            camera: snap.camera,
            crash: snap.crash,
            arming: snap.arming,
            watchEnabled: snap.watchEnabled,
            versionSupported: snap.versionSupported,
            clipSavedImmediately: snap.clipSavedImmediately,
            crashCancelWon: snap.crashCancelWon
        )
        let decision = RemoteCommandReducer.decide(input, cache: dedupe, now: now)

        dedupe.recording(
            command.commandId,
            reply: CommandDedupeCache.CachedReply(
                outcome: decision.outcome, reason: decision.reason,
                detail: decision.detail, newRideId: decision.newRideId
            ),
            at: now
        )
        if decision.outcome == .accepted {
            applyEffect(decision.effect)
        }

        return encodeReply(
            commandId: command.commandId, outcome: decision.outcome, reason: decision.reason,
            detail: decision.detail, newRideId: decision.newRideId, snap: snap, now: now
        )
    }

    // MARK: - Private

    /// Map the reducer `Effect` to a domain `RideRemoteCommand` and apply it
    /// through the bridge. The reducer already decided the outcome; the bridge is
    /// idempotent, so a failure never corrupts ride state.
    private func applyEffect(_ effect: RemoteCommandReducer.Effect) {
        let command: RideRemoteCommand?
        switch effect {
        case .none, .startFromWatch:
            // `startFromWatch` is handled by the arming/start path (task 23), not
            // the ride-engine bridge (rear-camera v1 has no start command there).
            command = nil
        case .pause: command = .pause
        case .resume: command = .resume
        case .stop: command = .stop(confirmedByHold: true)
        case .saveClip: command = .saveClip
        case .cancelCrashCountdown: command = .cancelCrashCountdown
        }
        guard let command else { return }
        onCommand?(command) { _ in }
    }

    /// Build a fresh `WireRideStatus` and wrap it in a `WireCommandReply`.
    private func encodeReply(
        commandId: String,
        outcome: WireCommandOutcome,
        reason: WireCommandReason?,
        detail: WireCommandDetail?,
        newRideId: String?,
        snap: Snapshot,
        now: Date
    ) -> WireEnvelope? {
        var status = mapper.map(
            snap.status, rideId: snap.rideId, epoch: snap.epoch, seq: seq,
            clipCount: snap.clipCount, demo: snap.isDemo,
            watchEnabled: snap.watchEnabled, now: now
        )
        status.crash = crashStatus(from: snap)
        status.start = startState(from: snap)

        let reply = WireCommandReply(
            commandId: commandId, outcome: outcome, reason: reason,
            detail: detail, newRideId: newRideId, status: status
        )
        return try? WireCodec.encode(
            reply, id: commandId, seq: seq, sentAt: now.timeIntervalSince1970
        )
    }

    /// Build the crash sub-object from the snapshot's crash phase, if any.
    private func crashStatus(from snap: Snapshot) -> WireCrashStatus? {
        guard let phase = snap.crash.phase, let eventId = snap.crash.eventId else { return nil }
        let remainingMs: Int
        if let deadline = snap.status.crashCountdownDeadline {
            remainingMs = max(0, Int(deadline.timeIntervalSince(snap.status.anchorDate) * 1000))
        } else {
            remainingMs = 0
        }
        return WireCrashStatus(
            eventId: eventId, remainingMs: remainingMs, isDrill: snap.isDemo,
            contactCount: 0, phase: phase
        )
    }

    /// Build the start-readiness sub-object from the arming snapshot.
    private func startState(from snap: Snapshot) -> WireStartState {
        switch snap.arming {
        case .armedReady:
            return .armed(untilMs: snap.armedUntilMs ?? 0)
        case let .armedNotReady(reasons):
            return .notReady(reasons)
        case .notArmed:
            return .ready
        }
    }

    /// A synthetic negotiated hello used only to form a `.ready` link state for
    /// the transport policy (the real handshake lives in the WC adapter). Its
    /// contents do not affect the live/context decision.
    private static let readyPeer = WireHello(
        minVersion: WireVersion.minSupported,
        maxVersion: WireVersion.current,
        appBuild: "phone",
        sessionNonce: "phone"
    )
}
