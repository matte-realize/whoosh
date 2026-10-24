import Foundation

/// Why the camera is running at a reduced profile while still recording
/// (rear-camera spec Requirement 12, design camera state-machine rows 7–8). A
/// `degraded` state keeps recording; it is not a stop.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraDegradeReason: String, Equatable, Codable, Sendable, CaseIterable {
    /// Thermal pressure stepped the profile down (fps, then resolution).
    case thermal
    /// Low battery / Low Power Mode forced the Efficient or Reduced profile.
    case battery
    /// Low free space reduced the effective ring cap and quality.
    case storage
}
