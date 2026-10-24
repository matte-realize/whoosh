import Foundation

/// A recoverable error from the segment recorder (rear-camera spec Requirement
/// 5/17.2, design camera state-machine rows 19–20). Maps to the reducer's
/// `writerFailed` event. Foundation-only so the Models/Metrics layers and tests
/// never import AVFoundation.
///
/// `String`-backed `Codable`, `Equatable`, `Sendable`, `CaseIterable`, `Error`.
enum SegmentRecorderError: String, Equatable, Codable, Sendable, CaseIterable, Error {
    /// The asset writer entered a failed state while writing a segment.
    case writerFailed = "writer_failed"
    /// The output file could not be created or written.
    case fileUnavailable = "file_unavailable"
}

/// Abstracts the rotating asset writer so the camera coordinator and tests never
/// touch AVFoundation (rear-camera spec Requirement 5, design "Service
/// protocols: SegmentRecording" and "Segment recorder"). `AssetWriterSegmentRecorder`
/// is the only concrete type that owns an `AVAssetWriter`; `FakeSegmentRecorder`
/// scripts finished segments and failures for tests and previews.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **Off the main actor, never blocks.** `append` is called on the capture
///   queue; when the writer is not ready the frame is dropped and counted —
///   nothing waits on `finishWriting`. Rotation starts the next writer on the
///   boundary frame so segment *n+1* begins with a keyframe.
/// - **Never stops GPS.** A writer failure discards the bad segment and triggers
///   the reducer's restart-once path; it never touches ride GPS recording.
/// - **On-device only.** Segment files are written to app storage, excluded from
///   backups, and never uploaded, linked, logged, or put in a message.
///
/// `AnyObject` because a recorder is a long-lived reference type owning the
/// writer and its serial queue. The frame type here is the Foundation-only
/// `CameraCaptureFrame` seam (not a `CMSampleBuffer`), so logic is testable
/// without AVFoundation.
@MainActor
protocol SegmentRecording: AnyObject {
    /// Invoked when a segment finishes and is ready to register with the store.
    var onSegmentFinished: ((SegmentInfo) -> Void)? { get set }

    /// Invoked when the writer fails (the reducer discards the segment and
    /// restarts once).
    var onFailure: ((SegmentRecorderError) -> Void)? { get set }

    /// Begin recording the first segment at the given profile and mount
    /// orientation. Must not block.
    func begin(profile: CaptureProfile, orientation: CameraMountOrientation)

    /// Append one captured frame to the current segment. Dropped and counted if
    /// the writer is not ready. Must not block.
    func append(_ frame: CameraCaptureFrame)

    /// Rotate to the next segment at the given boundary instant, finishing the
    /// current segment asynchronously. Must not block.
    func rotate(at boundary: Date)

    /// Finish the current segment and stop recording (ride end / teardown).
    func finish()
}
