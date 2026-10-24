import AVFoundation
import Foundation

/// The AVFoundation-backed `CameraPermission` (rear-camera spec Requirement 2,
/// task 20). The **only** concrete camera-authorization type; it lives in
/// `Services/Camera/` so capture-authorization APIs stay confined there
/// (privacy-check rule 7).
///
/// ## Contract (see privacy steering)
/// - **Requested only at the moment of use.** `request()` calls
///   `AVCaptureDevice.requestAccess(for: .video)` only when the rider enables
///   rear camera recording (the view model gates this behind the first-enable
///   explanation). It is never called at launch.
/// - **No re-prompt.** The system only prompts from `notDetermined`; from a
///   resolved state `request()` returns the current status unchanged (the rider
///   must change access in Settings).
/// - **Change propagation.** Returning from Settings can change authorization;
///   `refresh()` re-reads the system status and fires `onChange` so the Settings
///   UI updates without a restart. The composition root calls `refresh()` on
///   `scenePhase` becoming active.
/// - **Main actor.** Status and `onChange` are main-actor; `request()` hops to a
///   background continuation for the system call and resolves back on the main
///   actor, so the UI never blocks.
@MainActor
final class AVCameraPermission: CameraPermission {
    private(set) var status: CameraPermissionStatus
    var onChange: ((CameraPermissionStatus) -> Void)?

    init() {
        self.status = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    @discardableResult
    func request() async -> CameraPermissionStatus {
        // The system prompts only from notDetermined; a resolved state is
        // returned unchanged (matching `FakeCameraPermission`).
        guard status == .notDetermined else { return status }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        let newStatus: CameraPermissionStatus = granted ? .authorized : .denied
        if newStatus != status {
            status = newStatus
            onChange?(newStatus)
        } else {
            status = newStatus
        }
        return status
    }

    /// Re-read the system authorization (e.g. after returning from Settings) and
    /// notify if it changed. Safe to call repeatedly.
    func refresh() {
        let current = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        guard current != status else { return }
        status = current
        onChange?(current)
    }

    // MARK: - Mapping

    /// Map AVFoundation's authorization status to the Foundation-only enum.
    private static func map(_ status: AVAuthorizationStatus) -> CameraPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}
