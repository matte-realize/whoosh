import Foundation
import WhooshWire

/// The pure, phone-side decision table that turns a decoded wrist `WireCommand`
/// into a typed outcome and a *data* effect (watch-companion task 6, design
/// "`RemoteCommandReducer` — decision table"; Requirements 6.1–6.4, 6.10,
/// 7.2–7.7).
///
/// This is the authoritative guard between the watch and the ride engine. It is
/// a pure function of its inputs — it does **not** know the coordinators. The
/// caller (the `WatchRideRemote`) snapshots the current ride/camera/crash/arming
/// state into `Input`, checks the dedupe cache (row 1), runs `decide`, and then
/// executes the returned `Effect` on the main actor through the existing
/// intents. Undefined combinations are typed `ignored`/`rejected`/`alreadyInState`,
/// never thrown errors and never a crash (Requirement 6.10).
///
/// Row numbers below match the design table one-to-one and each is a unit test
/// (`RC-1 … RC-29`). `rideId` is checked first for every command except
/// `requestStart` (design note above the table).
///
/// Framework-free (Metrics layer: Models + `WhooshWire` + Foundation only).
enum RemoteCommandReducer {
    // MARK: - Inputs

    /// The crash-countdown situation relevant to a cancel (design rows 20–24).
    /// Expressed as plain data so the reducer needs no crash coordinator.
    struct CrashSnapshot: Equatable, Sendable {
        /// The current crash phase (`.countdown`, `.sending`, `.sent`, …);
        /// `nil` means no crash event is active.
        var phase: WireCrashPhase?
        /// The active event's id, if any (matched against the command's
        /// `crashEventId`).
        var eventId: String?

        init(phase: WireCrashPhase? = nil, eventId: String? = nil) {
            self.phase = phase
            self.eventId = eventId
        }

        static let none = CrashSnapshot()
    }

    /// The camera situation relevant to `saveClip` (design rows 15–18).
    struct CameraSnapshot: Equatable, Sendable {
        /// Camera is actively capturing (`recording` or `degraded`).
        var isRecording: Bool
        /// A save happened within the debounce window.
        var debounced: Bool
        /// Pinned-clip storage is full.
        var storageFull: Bool

        init(isRecording: Bool = false, debounced: Bool = false, storageFull: Bool = false) {
            self.isRecording = isRecording
            self.debounced = debounced
            self.storageFull = storageFull
        }

        static let off = CameraSnapshot()
    }

    /// Arming for `requestStart` (design rows 25–28). Mirrors `StartArming`.
    enum ArmingSnapshot: Equatable, Sendable {
        /// Armed and every start guard passes.
        case armedReady
        /// Armed but a start guard fails, with the sorted reason codes.
        case armedNotReady([WireStartReasonCode])
        /// Not armed.
        case notArmed
    }

    /// Everything the reducer needs. A value type the caller fills from a
    /// snapshot of the app, so `decide` is deterministic and fully testable.
    struct Input: Equatable, Sendable {
        var command: WireCommand
        /// The active ride's id (`nil` when `idle`/`finished`).
        var activeRideId: String?
        var rideState: RideState
        var camera: CameraSnapshot
        var crash: CrashSnapshot
        var arming: ArmingSnapshot
        /// "Apple Watch alerts and controls" setting is on.
        var watchEnabled: Bool
        /// The command's protocol version is supported by the phone.
        var versionSupported: Bool
        /// A `saveClip` that is accepted — was the clip saved now or pending?
        /// (`true` = already on disk, `false` = still being written.)
        var clipSavedImmediately: Bool
        /// A `cancelCrashCountdown` in the `.countdown` phase — did the cancel
        /// win the race (read back after the coordinator call). `true` =
        /// cancelled in time, `false` = too late.
        var crashCancelWon: Bool

        init(
            command: WireCommand,
            activeRideId: String? = nil,
            rideState: RideState = .idle,
            camera: CameraSnapshot = .off,
            crash: CrashSnapshot = .none,
            arming: ArmingSnapshot = .notArmed,
            watchEnabled: Bool = true,
            versionSupported: Bool = true,
            clipSavedImmediately: Bool = true,
            crashCancelWon: Bool = true
        ) {
            self.command = command
            self.activeRideId = activeRideId
            self.rideState = rideState
            self.camera = camera
            self.crash = crash
            self.arming = arming
            self.watchEnabled = watchEnabled
            self.versionSupported = versionSupported
            self.clipSavedImmediately = clipSavedImmediately
            self.crashCancelWon = crashCancelWon
        }
    }

    // MARK: - Output

    /// The side effect the bridge must run for an `accepted` command. Pure data;
    /// the reducer never calls a coordinator.
    enum Effect: Equatable, Sendable {
        case none
        case pause
        case resume
        case stop
        case saveClip
        case cancelCrashCountdown
        /// Start the ride from the wrist; the new ride id was generated by the
        /// caller and is echoed back in the reply.
        case startFromWatch(newRideId: String)
    }

    /// The reducer's verdict: the reply fields to send (minus the live status,
    /// which the caller attaches fresh) plus the effect to run. The design's
    /// "cached reply" row is represented by `fromCache`.
    struct Decision: Equatable, Sendable {
        var outcome: WireCommandOutcome
        var reason: WireCommandReason?
        var detail: WireCommandDetail?
        var newRideId: String?
        var effect: Effect
        /// True when row 1 hit the dedupe cache; the caller replays the cached
        /// reply instead of these synthesized fields.
        var fromCache: Bool

        init(
            outcome: WireCommandOutcome,
            reason: WireCommandReason? = nil,
            detail: WireCommandDetail? = nil,
            newRideId: String? = nil,
            effect: Effect = .none,
            fromCache: Bool = false
        ) {
            self.outcome = outcome
            self.reason = reason
            self.detail = detail
            self.newRideId = newRideId
            self.effect = effect
            self.fromCache = fromCache
        }
    }

    // MARK: - Decision table

    /// Run the table. `cache` and `now` are consulted for row 1 only; the caller
    /// records the resulting reply back into the cache after executing effects.
    static func decide(_ input: Input, cache: CommandDedupeCache, now: Date) -> Decision {
        let command = input.command

        // Row 1 — dedupe cache hit replays the exact prior reply.
        if cache.contains(command.commandId, at: now) {
            return Decision(outcome: .accepted, effect: .none, fromCache: true)
        }

        // Row 2 — unsupported protocol version.
        guard input.versionSupported else {
            return rejected(.unsupportedVersion)
        }

        // Row 3 — watch controls disabled.
        guard input.watchEnabled else {
            return rejected(.watchDisabled)
        }

        // Row 4 — stale ride id (every command except requestStart).
        if command.kind != .requestStart, command.kind != .unknown {
            if let target = command.rideId, target != input.activeRideId {
                return ignored(.staleRide)
            }
            // A command carrying no rideId falls through to the per-command
            // rows, which return `noActiveRide` when idle/finished — so a stale
            // id can never act on a new ride.
        }

        switch command.kind {
        case .pause:
            return decidePause(input)
        case .resume:
            return decideResume(input)
        case .stop:
            return decideStop(input)
        case .saveClip:
            return decideSaveClip(input)
        case .cancelCrashCountdown:
            return decideCancel(input)
        case .requestStart:
            return decideRequestStart(input)
        case .unknown:
            // Row 29 — unknown command.
            return rejected(.unknownCommand)
        }
    }

    // MARK: - Per-command rows

    private static func decidePause(_ input: Input) -> Decision {
        switch input.rideState {
        case .recording, .signalLost:
            return Decision(outcome: .accepted, effect: .pause)        // row 5
        case .paused:
            return Decision(outcome: .alreadyInState)                   // row 6
        case .idle, .finished:
            return ignored(.noActiveRide)                               // row 7
        }
    }

    private static func decideResume(_ input: Input) -> Decision {
        switch input.rideState {
        case .paused:
            return Decision(outcome: .accepted, effect: .resume)        // row 8
        case .recording, .signalLost:
            return Decision(outcome: .alreadyInState)                   // row 9
        case .idle, .finished:
            return ignored(.noActiveRide)                               // row 10
        }
    }

    private static func decideStop(_ input: Input) -> Decision {
        switch input.rideState {
        case .recording, .paused, .signalLost:
            guard input.command.holdConfirmed else {
                return rejected(.holdRequired)                          // row 12
            }
            return Decision(outcome: .accepted, effect: .stop)          // row 11
        case .finished:
            return Decision(outcome: .alreadyInState)                   // row 13
        case .idle:
            return ignored(.noActiveRide)                               // row 14
        }
    }

    private static func decideSaveClip(_ input: Input) -> Decision {
        // No active ride (row 19).
        guard input.rideState.isActive else {
            return ignored(.noActiveRide)
        }
        // Within the debounce window (row 16) — reports the last result code.
        if input.camera.debounced {
            let last: WireCommandDetail = input.camera.isRecording ? .pending : .cameraOff
            return Decision(outcome: .ignored, reason: .debounced, detail: last)
        }
        // Camera not recording (row 17).
        guard input.camera.isRecording else {
            return rejected(.cameraNotRecording, detail: .cameraOff)
        }
        // Pinned storage full (row 18).
                guard !input.camera.storageFull else {
                    // Row 18 — storage full. The reason is carried by the detail code.
                    return Decision(outcome: .rejected, detail: .storageFull)
                }
        // Accepted with saved/pending (row 15).
        let detail: WireCommandDetail = input.clipSavedImmediately ? .saved : .pending
        return Decision(outcome: .accepted, detail: detail, effect: .saveClip)
    }

    private static func decideCancel(_ input: Input) -> Decision {
        let command = input.command
        // Row 24 — no countdown at all, or a different event id.
        guard let phase = input.crash.phase, let activeId = input.crash.eventId else {
            return ignored(.noCountdown)
        }
        if let requested = command.crashEventId, requested != activeId {
            return ignored(.staleEvent)
        }

        switch phase {
        case .countdown:
            // Row 20 — cancel during the live countdown; detail read back after
            // the coordinator call.
            let detail: WireCommandDetail = input.crashCancelWon ? .cancelled : .tooLate
            return Decision(outcome: .accepted, detail: detail, effect: .cancelCrashCountdown)
        case .queuedOffline:
            // Row 21 — queued/retry-wait; rider cancel still wins.
            return Decision(outcome: .accepted, detail: .cancelled, effect: .cancelCrashCountdown)
        case .sending:
            // Row 22 — a dispatch is in flight; not cancellable. The reason is
            // carried by the detail code.
            return Decision(outcome: .rejected, detail: .notCancellable)
        case .sent, .cancelled, .stale:
            // Row 23 — already resolved.
            return Decision(outcome: .alreadyInState, detail: .tooLate)
        case .failed, .unknown:
            // Defensive: treat as nothing to cancel (row 24 spirit).
            return ignored(.noCountdown)
        }
    }

    private static func decideRequestStart(_ input: Input) -> Decision {
        // Row 28 — a ride is already active.
        if input.rideState != .idle {
            return rejected(.rideActive)
        }
        switch input.arming {
        case .armedReady:
            // Row 25 — armed, idle, all start guards pass.
            let newId = input.command.rideId ?? UUID().uuidString
            return Decision(outcome: .accepted, detail: .started, newRideId: newId,
                            effect: .startFromWatch(newRideId: newId))
        case .armedNotReady:
            // Row 27 — a start guard fails.
            return rejected(.notReady)
        case .notArmed:
            // Row 26 — not armed.
            return rejected(.notArmed)
        }
    }

    // MARK: - Builders

    private static func rejected(_ reason: WireCommandReason, detail: WireCommandDetail? = nil) -> Decision {
        Decision(outcome: .rejected, reason: reason, detail: detail)
    }

    private static func ignored(_ reason: WireCommandReason, detail: WireCommandDetail? = nil) -> Decision {
        Decision(outcome: .ignored, reason: reason, detail: detail)
    }
}
