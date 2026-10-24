import Foundation

/// The explicit camera-subsystem state (rear-camera spec Requirement 5.9,
/// design "Camera recording state machine"). Only the transitions in that table
/// are permitted; undefined transitions are no-ops. A camera state change never
/// affects the ride state or GPS points.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`. The associated
/// reasons/profiles are themselves `Codable`, so the whole state round-trips.
enum CameraRecordingState: Equatable, Codable, Sendable {
    /// Not recording (feature off, ride not started, or torn down).
    case off
    /// Starting the session and opening the first segment.
    case preparing
    /// Recording at the given profile.
    case recording(CaptureProfile)
    /// Still recording, but at a reduced profile for the given reason.
    case degraded(CaptureProfile, CameraDegradeReason)
    /// The session was interrupted (lock, call, other app); segment finalized.
    case interrupted(InterruptionReasonKind)
    /// Stopped by policy (thermal/storage/battery/permission) or ride end.
    case stopped(CameraStopReason)
    /// Tearing down at ride end / feature disable.
    case stopping
    /// Terminal failure after the retry budget; announced; GPS unaffected.
    case failed(CameraFailureReason)

    /// Whether the camera is actively capturing frames (recording or degraded).
    /// Detection only runs while this is true (seam update).
    var isRecording: Bool {
        switch self {
        case .recording, .degraded:
            return true
        case .off, .preparing, .interrupted, .stopped, .stopping, .failed:
            return false
        }
    }

    /// The profile currently in use, if any.
    var activeProfile: CaptureProfile? {
        switch self {
        case let .recording(profile), let .degraded(profile, _):
            return profile
        case .off, .preparing, .interrupted, .stopped, .stopping, .failed:
            return nil
        }
    }
}
