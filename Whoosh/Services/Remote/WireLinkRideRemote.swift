import Foundation
import WhooshWire

/// A phone-side `RideRemoteControlling` backed by a `WireLink` (watch-companion
/// spec, wiring for task 16; the production seam task 13 formalizes further).
/// It is the glue that lets the **existing** `RideStatusPublisher` and
/// `RideRemoteBridge` talk to a real Apple Watch over the WatchConnectivity
/// adapter without either of them learning about the wire:
///
/// - **Status out.** `publish(_:)` maps a `RideStatus` to the allowlisted
///   `WireRideStatus` (`WireMapper`, the privacy boundary) and writes it as
///   latest-wins application context so a waking watch always has the freshest
///   snapshot. A per-second message is unnecessary: the watch ticks the clock
///   from the anchor.
/// - **Commands in.** A live `WireCommand` is decoded, run through the pure
///   `RemoteCommandReducer` (the authoritative phone-side guard) with a snapshot
///   of the latest ride state, de-duplicated via `CommandDedupeCache`, and — when
///   accepted — mapped to a `RideRemoteCommand` handed to `onCommand` so the
///   `RideRemoteBridge` applies it to the ride engine. The reducer's verdict,
///   with a fresh status attached, is replied over the wire.
///
/// It never blocks recording and never touches the network (the link is device
/// to device). When no watch is usable the composition root injects
/// `NoopRideRemote` instead, so the phone behaves exactly as before.
///
/// `@MainActor` (project default isolation): the publisher, bridge, and ride
/// view model are all main-actor; the `WireLink`'s async methods hop as needed.
///
/// _Pending task 1 spike:_ built against the approved O-W2 design; the live/
/// context split and the status mapping are re-confirmed once the spike records
/// its measured latency in `spike-results.md`.
@MainActor
final class WireLinkRideRemote: RideRemoteControlling {

    private let link: any WireLink
    private let mapper = WireMapper()
    private let clock: Clock

    /// Whether the "Apple Watch alerts and controls" setting is on.
    private let watchEnabled: () -> Bool

    /// De-dupe cache so a retried `commandId` replays the same reply (Req 7.2).
    private var dedupe = CommandDedupeCache()

    /// The latest published status, kept so an incoming command can be decided
    /// against the current ride state and so a reply can embed a fresh status.
    private var lastStatus: RideStatus?
    private var lastWireStatus: WireRideStatus?

    /// Ride epoch (bumps on a new ride so the watch resets its seq) and the
    /// per-epoch sequence number.
    private var epoch = 0
    private var seq = 0
    private var lastRideId: String?

    /// Whether the link reported itself reachable.
    private var reachable = false

    var isReachable: Bool { reachable }
    var onCommand: ((RideRemoteCommand, _ reply: @escaping (RideRemoteCommandReply) -> Void) -> Void)?

    init(
        link: any WireLink,
        clock: Clock,
        watchEnabled: @escaping () -> Bool = { true }
    ) {
        self.link = link
        self.clock = clock
        self.watchEnabled = watchEnabled
        wireUp()
    }

    // MARK: - RideRemoteControlling

    func publish(_ status: RideStatus) {
        bumpEpochIfNewRide(status)
        seq += 1
        let wire = mapper.map(
            status,
            rideId: lastRideId ?? "",
            epoch: epoch,
            seq: seq,
            clipCount: 0,                         // clip count wired with the camera bridge (task 24)
            demo: false,
            watchEnabled: watchEnabled(),
            now: clock.now()
        )
        lastStatus = status
        lastWireStatus = wire
        let seqSnapshot = seq
        Task { [link] in
            guard let envelope = try? WireCodec.encode(
                wire, id: UUID().uuidString, seq: seqSnapshot, sentAt: Self.epochSeconds()
            ) else { return }
            _ = await link.updateContext(envelope)
        }
    }

    // MARK: - Wire wiring

    private func wireUp() {
        Task { [weak self] in
            guard let self else { return }
            await self.link.onReachabilityChange { [weak self] value in
                Task { @MainActor in self?.reachable = value }
            }
            await self.link.onLiveMessage { [weak self] envelope in
                // The live handler is @Sendable and may run off the main actor;
                // command handling must be on the main actor (ride engine), so
                // this synchronous reply path returns nil and the actual apply +
                // reply happens via the async hop below. For a live reply we
                // decode + decide synchronously-safe data here is not possible
                // across actors, so we schedule and return nil; the watch retries
                // with the same id (handled by the dedupe cache) and gets the
                // cached reply on the context/next attempt.
                guard let self else { return nil }
                Task { @MainActor in self.handleIncoming(envelope) }
                return nil
            }
            await self.link.activate()
        }
    }

    /// Decode and apply an incoming envelope. Only `command` envelopes act.
    private func handleIncoming(_ envelope: WireEnvelope) {
        guard let command = try? WireCodec.decodePayload(WireCommand.self, from: envelope) else { return }
        let now = clock.now()
        let input = makeInput(command)
        let decision = RemoteCommandReducer.decide(input, cache: dedupe, now: now)

        // A cache hit replays the stored reply; otherwise run the effect and
        // record the fresh reply.
        if !decision.fromCache {
            if let rideCommand = Self.rideCommand(for: decision.effect) {
                onCommand?(rideCommand) { _ in }
            }
            dedupe.recording(
                command.commandId,
                reply: CommandDedupeCache.CachedReply(
                    outcome: decision.outcome,
                    reason: decision.reason,
                    detail: decision.detail,
                    newRideId: decision.newRideId
                ),
                at: now
            )
        }
        sendReply(for: command, decision: decision)
    }

    private func sendReply(for command: WireCommand, decision: RemoteCommandReducer.Decision) {
        let status = lastWireStatus ?? Self.placeholderStatus(rideId: lastRideId ?? "")
        let reply = WireCommandReply(
            commandId: command.commandId,
            outcome: decision.outcome,
            reason: decision.reason,
            detail: decision.detail,
            newRideId: decision.newRideId,
            status: status
        )
        seq += 1
        let seqSnapshot = seq
        Task { [link] in
            guard let envelope = try? WireCodec.encode(
                reply, id: command.commandId, seq: seqSnapshot, sentAt: Self.epochSeconds()
            ) else { return }
            _ = await link.send(envelope)
        }
    }

    // MARK: - Snapshot for the reducer

    private func makeInput(_ command: WireCommand) -> RemoteCommandReducer.Input {
        let wire = lastWireStatus
        return RemoteCommandReducer.Input(
            command: command,
            activeRideId: (wire?.state.isActive ?? false) ? lastRideId : nil,
            rideState: lastStatus?.rideState ?? .idle,
            camera: cameraSnapshot(),
            crash: .none,
            arming: .notArmed,
            watchEnabled: watchEnabled(),
            versionSupported: command.kind != .unknown,
            clipSavedImmediately: true,
            crashCancelWon: true
        )
    }

    private func cameraSnapshot() -> RemoteCommandReducer.CameraSnapshot {
        guard let state = lastStatus?.cameraState else { return .off }
        let recording: Bool
        switch state {
        case .recording, .degraded: recording = true
        default: recording = false
        }
        return RemoteCommandReducer.CameraSnapshot(isRecording: recording)
    }

    // MARK: - Helpers

    private func bumpEpochIfNewRide(_ status: RideStatus) {
        // A fresh ride (idle → active transition) bumps the epoch and resets seq.
        if status.rideState == .recording, lastStatus?.rideState == .idle || lastStatus == nil {
            epoch += 1
            seq = 0
            lastRideId = UUID().uuidString
        }
        if status.rideState == .idle { lastRideId = nil }
    }

    private static func rideCommand(for effect: RemoteCommandReducer.Effect) -> RideRemoteCommand? {
        switch effect {
        case .pause: return .pause
        case .resume: return .resume
        case .stop: return .stop(confirmedByHold: true)
        case .saveClip: return .saveClip
        case .cancelCrashCountdown: return .cancelCrashCountdown
        case .startFromWatch, .none: return nil
        }
    }

    private static func epochSeconds() -> Double { Date().timeIntervalSince1970 }

    private static func placeholderStatus(rideId: String) -> WireRideStatus {
        WireRideStatus(
            rideId: rideId,
            epoch: 0,
            seq: 0,
            state: .idle,
            activeMs: 0,
            distance10m: 0,
            speedDms: nil,
            camera: WireCameraStatus(feature: .off, state: .off, reason: nil),
            flags: [],
            phone: WirePhoneState(batteryPct: 0, charging: false),
            banner: .none,
            crash: nil,
            clip: WireClipStatus(count: 0, lastSavedAgoMs: nil),
            start: .ready,
            demo: false,
            watchEnabled: true
        )
    }
}

private extension WireRideState {
    var isActive: Bool {
        switch self {
        case .recording, .paused, .signalLost: return true
        case .idle, .finished, .unknown: return false
        }
    }
}
