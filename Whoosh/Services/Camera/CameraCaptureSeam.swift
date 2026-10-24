import Foundation

/// Supporting value types for the `CameraCapturing` seam (rear-camera spec
/// Requirement 3/4, design "Service protocols: CameraCapturing"). These are the
/// Foundation-only inputs/outputs the capture service exchanges with its callers
/// and with its downstream sink.
///
/// ## Seam boundary (important for parallel work)
/// The full frame pipeline — `VideoFrame` (wrapping a `CVPixelBuffer`),
/// `FrameConsumer`, and the concrete `FramePipeline` — is defined by task 11 in
/// its own file and owns the pixel-buffer sendability contract. **Task 12 does
/// not define those types.** To let the capture seam and its fake be written and
/// tested before task 11 lands (task 12 depends only on task 2), the capture
/// service hands frames to a small `CameraFrameSink` seam that carries only
/// Foundation metadata — never a pixel buffer. The real `FramePipeline` conforms
/// to `CameraFrameSink` when the two streams merge; the fake drives it with
/// scripted metadata so the recorder/coordinator plumbing can be exercised now.

/// How the mounted phone is oriented, so the capture service can lock the video
/// orientation and the recorder can apply the matching transform. Derived from
/// gravity at Mount & frame (confirmed by the rider), then held for the ride.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CameraMountOrientation: String, Equatable, Codable, Sendable, CaseIterable {
    /// Home button / charge port to the right of the rear camera.
    case landscapeLeft = "landscape_left"
    /// Home button / charge port to the left of the rear camera.
    case landscapeRight = "landscape_right"
    /// Phone upright (portrait) on the mount.
    case portrait
    /// Phone upside down (portrait) on the mount.
    case portraitUpsideDown = "portrait_upside_down"
}

/// A request to step the capture profile up or down while recording (rear-camera
/// spec Requirement 12, design camera state-machine rows 7–8). Frame-rate
/// changes apply live; resolution changes happen at the next segment boundary.
/// The pure `ThermalPolicy`/`CaptureProfileSelector` decide *which* profile; this
/// is only the applied instruction the capture service receives.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct CaptureProfileStep: Equatable, Codable, Sendable {
    /// The profile to run after the step.
    let profile: CaptureProfile
    /// Why the profile changed (reduced for thermal/battery/storage, or back up).
    let reason: CameraDegradeReason?
    /// Whether the change can be applied live (fps only) or needs a boundary
    /// (resolution). The capture service uses this to decide when to apply it.
    let appliesLive: Bool

    init(profile: CaptureProfile, reason: CameraDegradeReason?, appliesLive: Bool) {
        self.profile = profile
        self.reason = reason
        self.appliesLive = appliesLive
    }
}

/// An event the capture service reports to its coordinator (rear-camera spec
/// Requirement 5.9/11/12, design camera state-machine events). Delivered on the
/// main actor; a camera event never changes the ride state or GPS points.
///
/// Foundation-only enum; `Equatable`, `Sendable`.
enum CameraCaptureEvent: Equatable, Sendable {
    /// The session is running and delivering frames at the given profile.
    case running(CaptureProfile)
    /// The session was interrupted (lock, call, other app); the open segment is
    /// finalized by the recorder.
    case interrupted(InterruptionReasonKind)
    /// A previous interruption ended; a new segment begins with a discontinuity.
    case interruptionEnded
    /// A runtime error on the capture session (retryable until the budget).
    case runtimeError
    /// System pressure changed to the given thermal level (maps to policy input).
    case systemPressureChanged(ThermalLevel)
}

/// A single captured frame's metadata, handed to a `CameraFrameSink`.
///
/// **Not** task 11's `VideoFrame`: this carries no `CVPixelBuffer`. It exists so
/// the capture seam and its fake can be written and tested without AVFoundation
/// or Core Video, and so the recorder/coordinator plumbing (frame counts,
/// ordering, discontinuity flags) is exercisable now. The real pipeline delivers
/// the image; this seam delivers the timing/ordering contract both agree on.
///
/// Foundation-only value type; `Equatable`, `Sendable`. `nonisolated` so the
/// capture service can build it on its video queue (off the main actor); it
/// crosses actors by its `Sendable` contract.
nonisolated struct CameraCaptureFrame: Equatable, Sendable {
    /// Monotonic capture-session time in seconds (ordering / intervals).
    let presentationTime: TimeInterval
    /// Wall-clock capture instant (the value a detector copies into a detection
    /// timestamp so clip windows align with the video).
    let capturedAt: Date
    /// Increasing integer per camera session.
    let sequence: Int
    /// `true` for the first frame after an interruption, restart, or format
    /// change.
    let isDiscontinuity: Bool

    init(
        presentationTime: TimeInterval,
        capturedAt: Date,
        sequence: Int,
        isDiscontinuity: Bool
    ) {
        self.presentationTime = presentationTime
        self.capturedAt = capturedAt
        self.sequence = sequence
        self.isDiscontinuity = isDiscontinuity
    }
}

/// The downstream seam the capture service feeds (rear-camera spec Requirement
/// 4). Task 11's concrete `FramePipeline` conforms to this when the streams
/// merge; `CameraFrameSink` is deliberately minimal so task 12 does not redefine
/// the pipeline. A sink must **never block** the capture queue — it accepts the
/// frame and returns immediately (the real pipeline uses latest-wins mailboxes).
///
/// `Sendable` because `offer` is called off the main actor on the capture queue.
protocol CameraFrameSink: Sendable {
    /// Offer a captured frame to the sink. Must return quickly and never block
    /// capture, the writer, or another consumer. `nonisolated` because it is
    /// called off the main actor on the capture queue.
    nonisolated func offer(_ frame: CameraCaptureFrame)
}
