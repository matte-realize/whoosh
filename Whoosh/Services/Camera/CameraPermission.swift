import Foundation

/// Abstracts the rear-camera authorization so the camera coordinator and the
/// Mount & frame / Settings flows are testable without AVFoundation (rear-camera
/// spec Requirement 2, design "Service protocols: CameraPermission").
///
/// ## Contract (non-negotiable; see privacy steering)
/// - **Requested only at the moment of use.** The camera prompt is shown only
///   when the rider first enables "Record rear camera" (after an in-app
///   explanation). A detector never requests camera access — permission belongs
///   to rear-camera recording, not to detection (seam update).
/// - **Only `authorized` permits capture.** `CameraPermissionStatus.canStartCapture`
///   gates the capture-session start (reducer rows 1–2).
/// - **Off-main safe.** `request()` is `async`; `status` and `onChange` are read
///   and delivered on the main actor (default isolation), so view models use
///   them directly. A permission change (including returning from Settings)
///   propagates through `onChange` without a restart.
/// - **Never stops GPS.** A camera-permission denial leaves ride GPS recording
///   unaffected; recording simply does not start and the state is announced,
///   never silent.
///
/// `AnyObject` because a concrete permission wrapper is a long-lived reference
/// type owning the system authorization observer. `FakeCameraPermission` scripts
/// the status and the async grant for tests and previews.
@MainActor
protocol CameraPermission: AnyObject {
    /// The current camera authorization state.
    var status: CameraPermissionStatus { get }

    /// Invoked whenever the authorization changes (grant, denial, or returning
    /// from Settings), so the UI updates without a restart (Requirement 2.4).
    var onChange: ((CameraPermissionStatus) -> Void)? { get set }

    /// Request camera access, returning the resulting status. A no-op that
    /// returns the current status when the state is already resolved
    /// (`authorized`/`denied`/`restricted`). Must not block the caller.
    @discardableResult
    func request() async -> CameraPermissionStatus
}
