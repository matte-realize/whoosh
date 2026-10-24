import Foundation
import WhooshWire

/// Maps the rear-camera `RideStatus` (the phone's full eyes-free snapshot, SI
/// units) to the allowlisted `WireRideStatus` sent to the watch (watch-companion
/// spec task 10; design "`WireMapper`"; Requirement 8, 19.1). Pure value type
/// (Metrics layer: Models + Foundation + the Foundation-only `WhooshWire`
/// package only).
///
/// **Privacy (Requirement 19.1):** the mapper is the allowlist boundary. It
/// copies only enums, rounded numbers, booleans, counts, and ids into
/// `WireRideStatus`; every other `RideStatus` field — coordinates, routes, the
/// free-text `banner`/degradation note — is **dropped**. Banner and camera
/// reasons become fixed codes, never the phone's free text, so no sensitive
/// string ever crosses the wire.
///
/// **Units:** distance is sent in 10 m units (`distance10m`), speed in 0.1 m/s
/// units (`speedDms`), both rounded to avoid false precision; the active
/// duration is sent as `activeMs` (the duration **at send**) so the watch ticks
/// it locally with `ElapsedTimeProjector` (design time rule L3). `rideId`,
/// `epoch`, and `seq` are supplied by the caller (`WatchRideRemote`), not by
/// `RideStatus`.
///
/// Crash countdown is **not** mapped here: `RideStatus` carries only a deadline,
/// while the wire needs the event id, contact count, and drill flag from the
/// crash coordinator. The remote attaches `WireCrashStatus` separately; the
/// mapper leaves `crash == nil`.
struct WireMapper: Sendable {

    init() {}

    /// Map a `RideStatus` to a `WireRideStatus`.
    ///
    /// - Parameters:
    ///   - status: the phone's full snapshot.
    ///   - rideId: the active ride's id (empty when idle).
    ///   - epoch: the ride epoch (bumps on a new ride so the watch resets seq).
    ///   - seq: the per-epoch sequence number (increases each publish).
    ///   - clipCount: how many clips are saved this ride.
    ///   - demo: whether the ride is a demo ride.
    ///   - watchEnabled: the "Apple Watch alerts and controls" setting.
    ///   - now: the instant used for relative ("ago") durations.
    func map(
        _ status: RideStatus,
        rideId: String,
        epoch: Int,
        seq: Int,
        clipCount: Int,
        demo: Bool,
        watchEnabled: Bool,
        now: Date
    ) -> WireRideStatus {
        WireRideStatus(
            rideId: rideId,
            epoch: epoch,
            seq: seq,
            state: Self.rideState(status.rideState),
            activeMs: Self.ms(status.activeDurationAnchor),
            distance10m: Self.distance10m(status.distanceMeters),
            speedDms: Self.speedDms(status.speedMetersPerSecond),
            camera: Self.camera(status.cameraState, stopReason: status.cameraStopReason),
            flags: Self.flags(status),
            phone: WirePhoneState(
                batteryPct: Self.pct(status.phoneBatteryPercent),
                charging: status.isCharging
            ),
            banner: Self.banner(status),
            crash: nil,                      // attached by WatchRideRemote (task 13)
            clip: WireClipStatus(
                count: max(0, clipCount),
                lastSavedAgoMs: Self.agoMs(status.lastClipSavedAt, now: now)
            ),
            start: .ready,                   // start/arming set by WatchRideRemote
            demo: demo,
            watchEnabled: watchEnabled
        )
    }

    // MARK: - Field mapping (pure)

    static func rideState(_ state: RideState) -> WireRideState {
        switch state {
        case .idle: return .idle
        case .recording: return .recording
        case .paused: return .paused
        case .signalLost: return .signalLost
        case .finished: return .finished
        }
    }

    /// Distance in 10 m units, rounded to the nearest unit, never negative.
    static func distance10m(_ meters: Double) -> Int {
        guard meters.isFinite, meters > 0 else { return 0 }
        return Int((meters / 10).rounded())
    }

    /// Speed in 0.1 m/s units, rounded; `nil` speed stays `nil`.
    static func speedDms(_ mps: Double?) -> Int? {
        guard let mps, mps.isFinite, mps >= 0 else { return nil }
        return Int((mps * 10).rounded())
    }

    /// Seconds → milliseconds, rounded, never negative.
    static func ms(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }

    /// Battery fraction 0…1 → integer percent 0…100.
    static func pct(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return min(100, max(0, Int((fraction * 100).rounded())))
    }

    /// Relative "ago" ms for a past timestamp, or `nil` if absent/in the future.
    static func agoMs(_ date: Date?, now: Date) -> Int? {
        guard let date else { return nil }
        let delta = now.timeIntervalSince(date)
        guard delta >= 0 else { return nil }
        return Int((delta * 1000).rounded())
    }

    /// Map the camera recording state + optional stop reason to the wire camera
    /// sub-object (feature on/off, state code, reason code). No framework text.
    static func camera(_ state: CameraRecordingState, stopReason: CameraStopReason?) -> WireCameraStatus {
        let feature: WireCameraFeature = (state == .off) ? .off : .on
        let wireState: WireCameraState
        var reason: WireCameraReason?

        switch state {
        case .off:
            wireState = .off
        case .preparing:
            wireState = .preparing
        case .recording:
            wireState = .recording
        case let .degraded(_, degradeReason):
            wireState = .degraded
            reason = Self.reason(fromDegrade: degradeReason)
        case .interrupted:
            wireState = .interrupted
            reason = .interrupted
        case let .stopped(stop):
            wireState = .stopped
            reason = Self.reason(fromStop: stop)
        case .stopping:
            wireState = .stopped
        case .failed:
            wireState = .failed
            reason = .failed
        }

        // A stop reason on the status (independent of the state) refines a
        // stopped/failed state when the state itself carried none.
        if reason == nil, let stopReason {
            reason = Self.reason(fromStop: stopReason)
        }
        return WireCameraStatus(feature: feature, state: wireState, reason: reason)
    }

    static func reason(fromStop stop: CameraStopReason) -> WireCameraReason? {
        switch stop {
        case .thermal: return .thermal
        case .storage: return .storage
        case .battery: return .battery
        case .permission: return .permission
        case .failed: return .failed
        case .rideEnded: return nil           // a normal end is not a trouble code
        }
    }

    static func reason(fromDegrade degrade: CameraDegradeReason) -> WireCameraReason {
        switch degrade {
        case .thermal: return .thermal
        case .battery: return .battery
        case .storage: return .storage
        }
    }

    /// Sorted set of transient phone flags derived from storage/thermal.
    static func flags(_ status: RideStatus) -> [WireStatusFlag] {
        var flags: [WireStatusFlag] = []
        if status.storageStatus != .ok { flags.append(.storageLow) }
        if status.thermalLevel >= .serious { flags.append(.phoneHot) }
        return flags.sorted()
    }

    /// Map the ride state to a banner code — never the phone's free-text banner.
    static func banner(_ status: RideStatus) -> WireBanner {
        switch status.rideState {
        case .signalLost:
            return .signalLost
        default:
            break
        }
        switch status.cameraState {
        case .failed:
            return .failed
        case .stopped(.permission):
            return .permissionRevoked
        default:
            return .none
        }
    }
}
