import Foundation

/// The rear-camera permission state (rear-camera spec Requirement 2, design
/// "Service protocols: CameraPermission"). Mirrors `AVAuthorizationStatus` but
/// stays Foundation-only so the Models/Metrics layers and tests never import
/// AVFoundation.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraPermissionStatus: String, Equatable, Codable, Sendable, CaseIterable {
    /// Not asked yet; the camera prompt will be shown when recording is enabled.
    case notDetermined = "not_determined"
    /// The rider granted camera access.
    case authorized
    /// The rider denied camera access; recording cannot start (Settings path).
    case denied
    /// Access is restricted by policy (e.g. parental controls).
    case restricted

    /// Whether the camera session may be started in this state. Only
    /// `authorized` permits capture (reducer guard, design row 1 / row 2).
    var canStartCapture: Bool { self == .authorized }
}
