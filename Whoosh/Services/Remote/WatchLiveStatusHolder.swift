import Foundation

/// A tiny mutable holder for the latest `WatchRideRemote.Snapshot` the phone
/// should publish to and answer the watch with (watch-companion tasks 16/17,
/// "make the watch live").
///
/// ## Why a holder
/// `PhoneRemoteFactory` builds the `WatchRideRemote` at app launch, long before
/// any ride session, camera coordinator, or crash countdown exists. The remote
/// needs a `@MainActor () -> Snapshot` closure both to publish status and to
/// decide an incoming command against the current ride state. This holder is the
/// seam: the factory wires the remote's snapshot closure to read `current` here,
/// and the `WatchLiveCoordinator` writes `current` ~1 Hz (and on every state or
/// crash-phase change) from the live ride/camera/crash state.
///
/// It defaults to an idle snapshot, so before any ride the watch sees a calm
/// "idle / ready" status and a command decided against idle (rejected/ignored) —
/// never a crash and never stale ride data.
///
/// `@MainActor` (project default isolation): read and written only on the main
/// actor, like everything in the remote/ride path.
@MainActor
final class WatchLiveStatusHolder {
    /// The latest snapshot to publish / decide against. Defaults to idle.
    var current: WatchRideRemote.Snapshot

    init(current: WatchRideRemote.Snapshot = .idle) {
        self.current = current
    }
}

extension WatchRideRemote.Snapshot {
    /// The all-idle snapshot used before any ride exists (no crash, not armed,
    /// nothing recording). The watch shows a calm idle/ready state.
    static var idle: WatchRideRemote.Snapshot {
        WatchRideRemote.Snapshot(
            status: RideStatus(
                rideState: .idle,
                activeDurationAnchor: 0,
                anchorDate: Date(),
                distanceMeters: 0,
                speedMetersPerSecond: nil,
                cameraState: .off,
                cameraStopReason: nil,
                storageStatus: .ok,
                thermalLevel: .nominal,
                phoneBatteryPercent: 0,
                isCharging: false,
                banner: nil,
                crashCountdownDeadline: nil,
                lastClipSavedAt: nil,
                lastDegradationNote: nil
            )
        )
    }
}
