import Foundation

/// Which built-in camera the rider records with (rear-camera spec task 17/20,
/// design D-CAM4 "back wide camera by default, with a front-camera option").
/// The **back wide camera is the default** (the phone is mounted facing
/// rearward); the front camera is offered for riders who mount the phone
/// screen-out. The choice is a persisted Settings value.
///
/// Mirrors the system camera position for the two positions the app uses but
/// stays Foundation-only so Models/Metrics and tests never import a capture
/// framework (the capture service maps it to the framework type).
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraDevicePosition: String, Equatable, Codable, Sendable, CaseIterable {
    /// The back wide-angle camera — the default for a rear-mounted phone.
    case back
    /// The front camera — for riders who mount the phone screen-out.
    case front

    /// A short display name for Settings.
    var displayName: String {
        switch self {
        case .back: return "Back"
        case .front: return "Front"
        }
    }
}
