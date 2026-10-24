import Foundation

/// Why the capture session was interrupted (rear-camera spec Requirement 11,
/// design camera state-machine row 9; iOS capability rows 1 and 19). Mirrors the
/// relevant AVFoundation capture-session interruption reasons but stays
/// Foundation-only so Models/Metrics never import AVFoundation.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum InterruptionReasonKind: String, Equatable, Codable, Sendable, CaseIterable {
    /// The app was sent to the background or the device was locked
    /// (`videoDeviceNotAvailableInBackground`). iOS cannot keep a third-party
    /// camera session alive here (capability row 1).
    case background
    /// An incoming/answered call or another app took the camera.
    case audioOrVideoDeviceInUse = "device_in_use"
    /// System pressure (thermal/power) forced the device unavailable.
    case systemPressure = "system_pressure"
    /// Any other/unknown interruption.
    case unknown
}
