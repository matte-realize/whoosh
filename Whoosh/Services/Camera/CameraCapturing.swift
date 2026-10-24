import Foundation

/// Abstracts the AVFoundation capture session so the camera coordinator, Mount &
/// frame, and tests never touch AVFoundation (rear-camera spec Requirement 3/4,
/// design "Service protocols: CameraCapturing"). `CameraCaptureService` is the
/// only concrete type that owns an `AVCaptureSession`; `FakeCameraCapture`
/// scripts state/events and feeds a `CameraFrameSink` for tests and previews.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **Off the main actor.** All capture work (session configuration,
///   sample-buffer callbacks) runs on dedicated serial queues. Only state and
///   events reach the main actor, where `onEvent` is delivered.
/// - **Non-blocking.** `start`/`stop`/`apply` return promptly; nothing a caller
///   or a downstream sink does may stall the capture queue.
/// - **Never stops GPS.** A capture failure, interruption, or teardown leaves
///   ride GPS recording untouched; every stop/degradation is announced, never
///   silent.
/// - **No footage leaves the device.** Frames are handed only to the local
///   `CameraFrameSink` and the recorder; capture never uploads, links, logs, or
///   transmits any frame or file.
///
/// `AnyObject` because a capture service is a long-lived reference type owning
/// the session. The frame sink and recorder are set before `start`.
@MainActor
protocol CameraCapturing: AnyObject {
    /// The sink captured frames are offered to (task 11's `FramePipeline` in the
    /// live app; a fake sink in tests). Set before `start`.
    var frameSink: CameraFrameSink? { get set }

    /// The recorder captured frames are also handed to for segment writing
    /// (`AssetWriterSegmentRecorder` live; `FakeSegmentRecorder` in tests). Set
    /// before `start`.
    var recorder: SegmentRecording? { get set }

    /// Delivered on the main actor as the session's state changes. A camera
    /// event never changes the ride state or GPS points.
    var onEvent: ((CameraCaptureEvent) -> Void)? { get set }

    /// Whether the session is currently running (between a successful `start`
    /// and `stop`/interruption).
    var isRunning: Bool { get }

    /// Start the session at `profile`, locked to `orientation`, with audio only
    /// when `audioEnabled` (off by default; O-CAM5). Opens the first segment on
    /// the recorder. Must not block.
    func start(profile: CaptureProfile, orientation: CameraMountOrientation, audioEnabled: Bool)

    /// Stop the session and tear down, releasing the camera (the system camera
    /// indicator turns off). Must not block.
    func stop()

    /// Apply a profile step (fps live, resolution at the next boundary). Must
    /// not block.
    func apply(_ step: CaptureProfileStep)
}
