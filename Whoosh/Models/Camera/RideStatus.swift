import Foundation

/// A read-only snapshot of the ride, published to eyes-free surfaces (rear-camera
/// spec Requirement 13, design "Eyes-free surfaces"). Built by `RideStatusPublisher`
/// from the ride bridge, the camera coordinator, battery, and the crash
/// coordinator; throttled by `StatusThrottle`. Never persisted.
///
/// The active duration is sent as an `anchorDate` plus the accumulated
/// `activeDurationAnchor` so a watch can tick the clock locally without a
/// message per second. Footage is never referenced here — only a camera *state*.
///
/// Foundation-only value type; `Equatable`, `Sendable`. Not `Codable`: a status
/// is a transient snapshot, never persisted (design "Entities": "value snapshot,
/// never persisted").
struct RideStatus: Equatable, Sendable {
    /// The ride lifecycle state (existing `RideState`).
    let rideState: RideState
    /// Accumulated active seconds at `anchorDate`.
    let activeDurationAnchor: TimeInterval
    /// The instant `activeDurationAnchor` was captured; the surface ticks from here.
    let anchorDate: Date
    /// Distance travelled in meters (SI; converted only in the formatting layer).
    let distanceMeters: Double
    /// Instantaneous speed in m/s, or `nil` when unknown.
    let speedMetersPerSecond: Double?
    /// Current camera subsystem state.
    let cameraState: CameraRecordingState
    /// Why the camera stopped, when stopped.
    let cameraStopReason: CameraStopReason?
    /// Current free-space status.
    let storageStatus: StorageStatus
    /// Current thermal level.
    let thermalLevel: ThermalLevel
    /// Phone battery fraction in 0...1.
    let phoneBatteryPercent: Double
    /// Whether the phone is charging.
    let isCharging: Bool
    /// A short banner message for the surface, if any.
    let banner: String?
    /// The absolute deadline of an active crash countdown, if any.
    let crashCountdownDeadline: Date?
    /// When the last clip was saved, if any (for a "clip saved" cue).
    let lastClipSavedAt: Date?
    /// A short note describing the last camera degradation, if any.
    let lastDegradationNote: String?

    init(
        rideState: RideState,
        activeDurationAnchor: TimeInterval,
        anchorDate: Date,
        distanceMeters: Double,
        speedMetersPerSecond: Double?,
        cameraState: CameraRecordingState,
        cameraStopReason: CameraStopReason?,
        storageStatus: StorageStatus,
        thermalLevel: ThermalLevel,
        phoneBatteryPercent: Double,
        isCharging: Bool,
        banner: String?,
        crashCountdownDeadline: Date?,
        lastClipSavedAt: Date?,
        lastDegradationNote: String?
    ) {
        self.rideState = rideState
        self.activeDurationAnchor = activeDurationAnchor
        self.anchorDate = anchorDate
        self.distanceMeters = distanceMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.cameraState = cameraState
        self.cameraStopReason = cameraStopReason
        self.storageStatus = storageStatus
        self.thermalLevel = thermalLevel
        self.phoneBatteryPercent = phoneBatteryPercent
        self.isCharging = isCharging
        self.banner = banner
        self.crashCountdownDeadline = crashCountdownDeadline
        self.lastClipSavedAt = lastClipSavedAt
        self.lastDegradationNote = lastDegradationNote
    }
}
