import Foundation

/// The ride status published from phone to watch (watch-companion design
/// "`WireRideStatus`"; Requirement 8). Mapped from the rear-camera `RideStatus`
/// by the phone's `WireMapper`, which drops every field outside this allowlist.
///
/// **Privacy (Requirement 19.1):** enums, rounded numbers, booleans, counts, and
/// ids only. No coordinates, route, map data, video, thumbnails, clip ids,
/// contact names or numbers, or message text.
///
/// Time is skew-free: `activeMs` is the active duration **at send**; the watch
/// advances it with its own monotonic clock while `recording`/`signalLost` and
/// freezes it when `paused` (`ElapsedTimeProjector`). `distance10m` is distance
/// in 10 m units; `speedDms` is 0.1 m/s units (rounded to avoid false
/// precision; Requirement 5.6).
public struct WireRideStatus: Equatable, Codable, Sendable {
    public var rideId: String
    public var epoch: Int
    public var seq: Int
    public var state: WireRideState
    public var activeMs: Int
    public var distance10m: Int
    public var speedDms: Int?
    public var camera: WireCameraStatus
    /// Sorted set of transient flags (storageLow, phoneHot, lowPowerMode).
    public var flags: [WireStatusFlag]
    public var phone: WirePhoneState
    public var banner: WireBanner
    public var crash: WireCrashStatus?
    public var clip: WireClipStatus
    public var start: WireStartState
    public var demo: Bool
    public var watchEnabled: Bool

    public init(
        rideId: String,
        epoch: Int,
        seq: Int,
        state: WireRideState,
        activeMs: Int,
        distance10m: Int,
        speedDms: Int? = nil,
        camera: WireCameraStatus,
        flags: [WireStatusFlag] = [],
        phone: WirePhoneState,
        banner: WireBanner = .none,
        crash: WireCrashStatus? = nil,
        clip: WireClipStatus = WireClipStatus(count: 0),
        start: WireStartState = .ready,
        demo: Bool = false,
        watchEnabled: Bool = true
    ) {
        self.rideId = rideId
        self.epoch = epoch
        self.seq = seq
        self.state = state
        self.activeMs = activeMs
        self.distance10m = distance10m
        self.speedDms = speedDms
        self.camera = camera
        self.flags = flags.sorted()
        self.phone = phone
        self.banner = banner
        self.crash = crash
        self.clip = clip
        self.start = start
        self.demo = demo
        self.watchEnabled = watchEnabled
    }
}
