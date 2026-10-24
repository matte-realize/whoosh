import Foundation

/// A single point in a bundled, timestamped scripted route for the simulated
/// ride (demo-mode design "Data: the scripted route"). Pure, Foundation-only so
/// it lives in the Models layer and is unit-testable without a device.
///
/// `offsetSeconds` is the point's time from ride start (monotonically
/// increasing). The player schedules each point's delivery through the injected
/// `Clock`, scaled by the playback speed factor, and converts it to a
/// `RoutePoint` (using a ride-start `Date`) exactly as a real GPS fix would be.
struct ScriptedRoutePoint: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Seconds from ride start; strictly increasing across a script.
    let offsetSeconds: TimeInterval
    /// Instantaneous speed in meters/second (`< 0` when unknown, matching
    /// Core Location's convention).
    let speedMetersPerSecond: Double
    /// Horizontal accuracy radius in meters; larger is worse.
    let horizontalAccuracyMeters: Double
    /// Optional segment marker (pause / signal-loss boundaries).
    let marker: ScriptedRouteMarker?

    init(
        latitude: Double,
        longitude: Double,
        offsetSeconds: TimeInterval,
        speedMetersPerSecond: Double,
        horizontalAccuracyMeters: Double,
        marker: ScriptedRouteMarker? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.offsetSeconds = offsetSeconds
        self.speedMetersPerSecond = speedMetersPerSecond
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.marker = marker
    }
}

/// Segment boundaries carried by a `ScriptedRoutePoint` so the script expresses
/// a pause segment and a short signal-loss gap without the ride engine needing
/// any special-casing (demo-mode design "Data: the scripted route").
enum ScriptedRouteMarker: Equatable, Hashable, Sendable {
    /// First point of a pause segment (the rider is stopped).
    case pauseStart
    /// First point after a pause segment (the rider resumes).
    case pauseEnd
    /// Start of a window during which the player withholds points so the real
    /// amber signal-lost banner appears.
    case signalLossStart
    /// First point after the signal-loss window (points resume).
    case signalLossEnd

    // Pattern-match helpers usable from nonisolated contexts (pure Metrics
    // functions) without relying on the synthesized `Equatable` conformance,
    // which the Swift 6 default-MainActor isolation infers as main-actor-bound.
    nonisolated var isPauseStart: Bool { if case .pauseStart = self { return true }; return false }
    nonisolated var isPauseEnd: Bool { if case .pauseEnd = self { return true }; return false }
    nonisolated var isSignalLossStart: Bool { if case .signalLossStart = self { return true }; return false }
    nonisolated var isSignalLossEnd: Bool { if case .signalLossEnd = self { return true }; return false }
}
