import Foundation

/// Scriptable `SegmentRecording` for tests and SwiftUI previews. It records the
/// lifecycle calls and appended frames, and can be scripted to finish segments
/// (through `rotate`/`finish` or `finishSegment(_:)`) and to fail, so the ring
/// manager and coordinator (tasks 18/19) can be exercised without AVFoundation.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - `begin` / `append` / `rotate` / `finish` behave like the real recorder's
///   observable effects: `begin` opens a segment, `append` counts a frame,
///   `rotate` closes the open segment (emitting a `SegmentInfo` built from the
///   recorded frames) and opens the next, `finish` closes the open segment.
/// - Override the emitted `SegmentInfo` with `finishSegment(_:)`, or fail with
///   `fail(_:)`.
/// Callbacks fire synchronously on the main actor so expectations are
/// deterministic. The fake never writes or transmits real media.
@MainActor
final class FakeSegmentRecorder: SegmentRecording {
    var onSegmentFinished: ((SegmentInfo) -> Void)?
    var onFailure: ((SegmentRecorderError) -> Void)?

    /// The ride id stamped on emitted segments (set by whoever drives the fake).
    var rideId: UUID
    /// Synthetic bytes attributed to each finished segment.
    var bytesPerSegment: Int64

    // MARK: Recorded interactions (for test assertions)

    /// Number of `begin` calls.
    private(set) var beginCount = 0
    /// The `(profile, orientation)` of the most recent `begin`.
    private(set) var lastBegin: (profile: CaptureProfile, orientation: CameraMountOrientation)?
    /// Every appended frame, in order.
    private(set) var appendedFrames: [CameraCaptureFrame] = []
    /// Number of `rotate` calls.
    private(set) var rotateCount = 0
    /// Number of `finish` calls.
    private(set) var finishCount = 0
    /// Every segment emitted through `onSegmentFinished`, in order.
    private(set) var finishedSegments: [SegmentInfo] = []

    private var segmentIndex = 0
    private var openSegmentStart: Date?
    private var framesInOpenSegment: [CameraCaptureFrame] = []
    private var nextSegmentHasGapBefore = false

    init(
        rideId: UUID = UUID(),
        bytesPerSegment: Int64 = 37_500_000 / 4
    ) {
        self.rideId = rideId
        self.bytesPerSegment = bytesPerSegment
    }

    // MARK: SegmentRecording

    func begin(profile: CaptureProfile, orientation: CameraMountOrientation) {
        beginCount += 1
        lastBegin = (profile, orientation)
        openSegmentStart = nil
        framesInOpenSegment = []
    }

    func append(_ frame: CameraCaptureFrame) {
        appendedFrames.append(frame)
        if openSegmentStart == nil { openSegmentStart = frame.capturedAt }
        if frame.isDiscontinuity && !framesInOpenSegment.isEmpty {
            nextSegmentHasGapBefore = true
        }
        framesInOpenSegment.append(frame)
    }

    func rotate(at boundary: Date) {
        rotateCount += 1
        closeOpenSegment(end: boundary)
    }

    func finish() {
        finishCount += 1
        closeOpenSegment(end: lastFrameTime)
    }

    // MARK: Scripting API (test/preview driven)

    /// Emit an explicit `SegmentInfo` through `onSegmentFinished`, bypassing the
    /// built-from-frames path.
    func finishSegment(_ segment: SegmentInfo) {
        finishedSegments.append(segment)
        onSegmentFinished?(segment)
    }

    /// Deliver a failure through `onFailure`.
    func fail(_ error: SegmentRecorderError) {
        onFailure?(error)
    }

    // MARK: Private

    private var lastFrameTime: Date? {
        framesInOpenSegment.last?.capturedAt
    }

    private func closeOpenSegment(end: Date?) {
        guard let start = openSegmentStart else { return }
        let profileName = lastBegin?.profile.name ?? CaptureProfile.standard.name
        let segment = SegmentInfo(
            id: UUID(),
            rideId: rideId,
            index: segmentIndex,
            start: start,
            end: end ?? start,
            bytes: bytesPerSegment,
            profileName: profileName,
            hasAudio: false,
            isPinned: false,
            hasGapBefore: nextSegmentHasGapBefore
        )
        segmentIndex += 1
        nextSegmentHasGapBefore = false
        openSegmentStart = nil
        framesInOpenSegment = []
        finishSegment(segment)
    }
}
