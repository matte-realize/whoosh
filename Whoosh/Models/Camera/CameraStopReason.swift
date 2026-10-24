import Foundation

/// Why the camera subsystem stopped recording by policy or failure (rear-camera
/// spec Requirement 12, design camera state-machine rows 12–20). Surfaced to the
/// rider on the eyes-free surface and noted in the ride summary — a camera stop
/// is never silent.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraStopReason: String, Equatable, Codable, Sendable, CaseIterable {
    /// Thermal critical / system-pressure shutdown risk.
    case thermal
    /// Free space dropped below the stop floor.
    case storage
    /// Battery at or below the stop floor and not charging.
    case battery
    /// Camera permission was revoked mid-ride.
    case permission
    /// The capture session or asset writer failed and could not be restarted.
    case failed
    /// The ride ended or the feature was disabled.
    case rideEnded = "ride_ended"
}
