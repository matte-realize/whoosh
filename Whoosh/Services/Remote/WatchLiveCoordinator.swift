import Foundation
import WhooshWire

/// Keeps the Apple Watch live during a ride and a crash countdown (watch-companion
/// tasks 16/17/21; "make the watch live"). It is the phone-side driver that turns
/// the live ride session, camera coordinator, and crash coordinator into the
/// `RideStatus` + `WatchRideRemote.Snapshot` the watch displays, writes that into
/// the shared `WatchLiveStatusHolder` (so an incoming wrist command is decided
/// against the current state), and publishes it to the `remote` about once a
/// second.
///
/// ## What it publishes
/// - **Ride numbers / camera state** from the ride session and camera
///   coordinator, mapped to the allowlisted wire fields by `WireMapper` inside
///   the remote (no coordinates, route, or footage ever cross the wire).
/// - **Crash countdown** from the crash coordinator: when a countdown is active
///   (real or a demo **drill**), the snapshot carries the event id, remaining
///   time (as an absolute deadline), drill flag, contact count, and phase, so the
///   watch shows its full-screen Cancel takeover. This works **even with no
///   active ride** (a demo drill from Home), because the coordinator publishes a
///   crash-only idle status in that case.
///
/// ## Lifecycle
/// `start()` activates the remote and begins the ~1 Hz tick. `attach(ride:camera:)`
/// binds the live ride; `detachRide()` clears it. `stop()` ends the tick and
/// publishes a final idle status. When no usable watch is paired the `remote` is
/// a `NoopRideRemote` and every publish is a harmless no-op, so the ride flow is
/// unchanged (Requirement 1.5).
///
/// `@MainActor` (project default isolation): the ride view model, camera
/// coordinator, and crash coordinator are all main-actor.
@MainActor
final class WatchLiveCoordinator {
    private let remote: RideRemoteControlling
    private let holder: WatchLiveStatusHolder
    private let crash: CrashResponseCoordinator
    private let clock: Clock
    /// Whether the active ride is a demo ride (set by the app from demo state).
    private let isDemoRide: () -> Bool

    /// The current live ride session, if any.
    private weak var ride: RideSessionViewModel?
    /// The current camera coordinator, if any (clip count + camera state).
    private weak var camera: CameraRecordingCoordinator?

    /// The ~1 Hz publish timer.
    private var tickTimer: Cancellable?
    /// A monotonically increasing epoch so the watch resets its sequence when a
    /// new ride (or a fresh countdown with no ride) begins.
    private var epoch = 0
    /// The last ride id we published under, to bump the epoch on a new ride.
    private var lastRideId: UUID?

    init(
        remote: RideRemoteControlling,
        holder: WatchLiveStatusHolder,
        crash: CrashResponseCoordinator,
        clock: Clock,
        isDemoRide: @escaping () -> Bool = { false }
    ) {
        self.remote = remote
        self.holder = holder
        self.crash = crash
        self.clock = clock
        self.isDemoRide = isDemoRide
    }

    // MARK: - Lifecycle

    /// Activate the remote link and begin publishing ~1 Hz. Idempotent.
    func start() {
        Task { await activateRemoteIfNeeded() }
        guard tickTimer == nil else { return }
        scheduleTick()
        publishNow()
    }

    /// Bind the live ride session + camera coordinator so the published status
    /// reflects real ride numbers and camera state. Bumps the epoch for a new
    /// ride so the watch resets its sequence.
    func attach(ride: RideSessionViewModel, camera: CameraRecordingCoordinator?) {
        self.ride = ride
        self.camera = camera
        start()
        publishNow()
    }

    /// Clear the ride binding (ride finished / cleared). Keeps publishing so a
    /// crash countdown drill with no ride still reaches the wrist; the app calls
    /// `stop()` when it no longer needs the watch live.
    func detachRide() {
        ride = nil
        camera = nil
        publishNow()
    }

    /// Stop the tick and publish a final idle status.
    func stop() {
        tickTimer?.cancel()
        tickTimer = nil
        ride = nil
        camera = nil
        holder.current = .idle
        remote.publish(WatchLiveStatusHolder.Snapshot.idle.status)
    }

    /// Publish immediately (e.g. the crash countdown just started or ended, or a
    /// ride state changed). Safe to call any time.
    func publishNow() {
        let snapshot = buildSnapshot()
        holder.current = snapshot
        remote.publish(snapshot.status)
    }

    // MARK: - Private

    private func activateRemoteIfNeeded() async {
        if let watchRemote = remote as? WatchRideRemote {
            await watchRemote.activate()
        }
    }

    private func scheduleTick() {
        tickTimer = clock.schedule(after: 1) { [weak self] in
            guard let self else { return }
            self.publishNow()
            self.scheduleTick()
        }
    }

    /// Build the full `WatchRideRemote.Snapshot` from the live ride, camera, and
    /// crash state.
    private func buildSnapshot() -> WatchRideRemote.Snapshot {
        let now = clock.now()
        let status = buildRideStatus(now: now)
        let crashSnap = buildCrashSnapshot()

        // Bump the epoch on a new ride so the watch resets its sequence.
        let rideId = ride?.currentRideID
        if rideId != lastRideId {
            if rideId != nil { epoch += 1 }
            lastRideId = rideId
        }

        // A drill is a demo event; a demo ride is a demo ride. Either marks the
        // snapshot demo so the wrist countdown labels it DEMO (and the mapper
        // flags the ride as demo).
        let demo = isDemoRide() || crash.isDrill

        return WatchRideRemote.Snapshot(
            status: status,
            rideId: rideId?.uuidString ?? "",
            epoch: epoch,
            clipCount: 0,
            isDemo: demo,
            watchEnabled: true,
            camera: cameraCommandSnapshot(),
            crash: crashSnap,
            arming: .notArmed,
            armedUntilMs: nil,
            versionSupported: true,
            clipSavedImmediately: true,
            crashCancelWon: true
        )
    }

    /// Build the `RideStatus` the mapper turns into wire fields. When there is no
    /// ride, the ride fields are idle but the crash deadline is still carried so
    /// a drill-from-Home shows its countdown on the wrist.
    private func buildRideStatus(now: Date) -> RideStatus {
        let rideState = ride?.rideState ?? .idle
        let activeDuration = ride?.activeDuration(at: now) ?? 0
        let distance = ride?.distanceMeters ?? 0
        let speed = ride?.points.last?.speedMetersPerSecond
        let cameraState = camera?.state ?? .off

        return RideStatus(
            rideState: rideState,
            activeDurationAnchor: activeDuration,
            anchorDate: now,
            distanceMeters: distance,
            speedMetersPerSecond: (speed ?? -1) >= 0 ? speed : nil,
            cameraState: cameraState,
            cameraStopReason: nil,
            storageStatus: .ok,
            thermalLevel: .nominal,
            phoneBatteryPercent: 0,
            isCharging: false,
            banner: nil,
            crashCountdownDeadline: crashDeadline(now: now),
            lastClipSavedAt: nil,
            lastDegradationNote: nil
        )
    }

    /// The crash sub-object the remote attaches to the wire status, derived from
    /// the crash coordinator's live state. `nil` when no countdown is active.
    private func buildCrashSnapshot() -> RemoteCommandReducer.CrashSnapshot {
        guard let phase = wirePhase(crash.eventState), let eventId = crash.eventId else {
            return .none
        }
        return RemoteCommandReducer.CrashSnapshot(phase: phase, eventId: eventId)
    }

    /// The absolute countdown deadline (so the wire can send remaining time),
    /// anchored to `now` + remaining seconds. `nil` unless counting down.
    private func crashDeadline(now: Date) -> Date? {
        guard crash.eventState == .countdown, let remaining = crash.remainingSeconds else {
            return nil
        }
        return now.addingTimeInterval(TimeInterval(remaining))
    }

    private func cameraCommandSnapshot() -> RemoteCommandReducer.CameraSnapshot {
        let recording = camera?.state.isRecording ?? false
        return RemoteCommandReducer.CameraSnapshot(isRecording: recording)
    }

    /// Map the crash-event state to the wire phase the watch understands.
    private func wirePhase(_ state: CrashEventState) -> WireCrashPhase? {
        switch state {
        case .countdown: return .countdown
        case .cancelled: return .cancelled
        case .sending: return .sending
        case .queuedOffline: return .queuedOffline
        case .sent: return .sent
        case .failed: return .failed
        case .stale: return .stale
        case .idle, .detected, .fallbackPrompted, .recoveryPrompted:
            return nil
        }
    }
}

private extension CrashResponseCoordinator {
    /// The active event's id as a `String`, if any (wire ids are strings).
    var eventId: String? { machine.eventId?.uuidString }
}

private extension WatchLiveStatusHolder {
    /// Convenience alias so the file reads `WatchLiveStatusHolder.Snapshot`.
    typealias Snapshot = WatchRideRemote.Snapshot
}
