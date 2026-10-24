import CoreVideo
import Foundation

/// One camera frame handed to `FrameConsumer`s through the `FramePipeline`
/// (rear-camera spec task 11, Requirement 4.1; design "VideoFrame"). This is the
/// value Teammate B's detector reads; the shape is **frozen** by the contract
/// freeze (design "Frame pipeline and the consumer contract") and does not change
/// without a 3-way OK (iOS, Teammate B, Role C).
///
/// ## Swift 6 sendability (design capability row 20)
/// `CVPixelBuffer` is a Core Video reference type and is **not** `Sendable`.
/// Frames cross actors (the capture serial queue → each consumer's own
/// executor), so `VideoFrame` is marked `@unchecked Sendable` and carries an
/// **immutability contract**: the pixel buffer is treated as read-only by every
/// consumer. The capture service hands each frame to the pipeline and does not
/// mutate or recycle the buffer while it is in flight; a consumer that needs to
/// keep or mutate pixels MUST copy (design backpressure rule 6). This is the
/// documented, reviewed exception the steering allows for a pixel-buffer wrapper;
/// no other mutable state is stored here.
///
/// Time is expressed two ways:
/// - `presentationTime` — a monotonic capture-session time in **seconds**, for
///   ordering and inter-frame intervals (what `FrameDropPolicy` reasons over).
/// - `capturedAt` — the wall-clock `Date` of capture; **this is the value a
///   detector copies into `HazardDetection.timestamp`** so clip windows align
///   with the video.
nonisolated struct VideoFrame: @unchecked Sendable {
    /// How a buffer must be rotated to be upright for the chosen mount
    /// orientation. Maps to Vision's `CGImagePropertyOrientation`; kept as a
    /// framework-free enum here so Models/Metrics-adjacent code and tests need no
    /// AVFoundation/Vision import. A detector translates it when calling Vision.
    enum DisplayOrientation: Int, Equatable, Sendable {
        case up = 1
        case down = 3
        case left = 6
        case right = 8
    }

    /// Lightweight description of the frame's pixel format and active rate, so a
    /// consumer can configure itself at `pipelineDidStart(format:)` without
    /// touching the buffer. Framework-free.
    struct Format: Equatable, Sendable {
        let width: Int
        let height: Int
        /// Core Video pixel-format FourCC (e.g. the 4:2:0 bi-planar formats).
        let pixelFormat: OSType
        /// The capture frame rate currently active.
        let framesPerSecond: Int

        init(width: Int, height: Int, pixelFormat: OSType, framesPerSecond: Int) {
            self.width = width
            self.height = height
            self.pixelFormat = pixelFormat
            self.framesPerSecond = framesPerSecond
        }
    }

    /// The image. **Read-only by contract** (see the type doc); copy before
    /// retaining or mutating.
    let pixelBuffer: CVPixelBuffer
    /// Monotonic capture-session time in seconds (ordering / intervals).
    let presentationTime: TimeInterval
    /// Wall-clock capture time; the value a detector copies into
    /// `HazardDetection.timestamp`.
    let capturedAt: Date
    /// How the buffer must be rotated to be upright for the mount.
    let orientation: DisplayOrientation
    /// Increasing integer per camera session.
    let sequence: Int
    /// True for the first frame after an interruption, restart, or format change
    /// so a consumer can reset temporal state (Requirement 4.8).
    let isDiscontinuity: Bool
    /// The active format for this frame.
    let format: Format

    init(
        pixelBuffer: CVPixelBuffer,
        presentationTime: TimeInterval,
        capturedAt: Date,
        orientation: DisplayOrientation,
        sequence: Int,
        isDiscontinuity: Bool,
        format: Format
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.capturedAt = capturedAt
        self.orientation = orientation
        self.sequence = sequence
        self.isDiscontinuity = isDiscontinuity
        self.format = format
    }
}
