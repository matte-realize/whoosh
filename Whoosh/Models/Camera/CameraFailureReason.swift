import Foundation

/// Why the camera subsystem entered the terminal `failed` state (rear-camera
/// spec Requirement 17.2, design camera state-machine rows 6 and 20). A failure
/// is announced and never affects GPS recording.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraFailureReason: String, Equatable, Codable, Sendable, CaseIterable {
    /// The capture session could not start after the retry budget (row 6).
    case startTimeout = "start_timeout"
    /// A runtime error on the capture session that retries did not clear.
    case runtimeError = "runtime_error"
    /// The asset writer failed and the single restart also failed (row 20).
    case writer
}
