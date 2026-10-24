import AVFoundation
import CoreMedia
import Foundation
import OSLog

/// The only `AVAssetWriter` owner (rear-camera spec task 18; Requirements
/// 5.1–5.8, 5.10, 19.4). One writer per fixed-length segment, HEVC with an
/// H.264 fallback, movie fragments so a file stays playable if the process
/// dies, rotation on the boundary frame without blocking capture, drop-when-not-
/// ready with a counter, and a fragment-safe finalize.
///
/// Split in two so the hot pixel path is never main-actor-bound:
/// - `AssetWriterSegmentRecorder` (`@MainActor`) conforms to `SegmentRecording`;
///   the coordinator and ring manager drive it through the Foundation-only seam.
///   It also builds the `SegmentInfo` the seam exposes and the AVFoundation video
///   settings/transform, so the domain value types stay on the main actor.
/// - `SegmentWriterCore` (`nonisolated`, `@unchecked Sendable`, lock-guarded) owns
///   the `AVAssetWriter` state and runs on the capture serial queue. It traffics
///   only in primitives and AVFoundation types and reports a finished segment as
///   raw numbers (`FinishedSegment`), which the wrapper maps to `SegmentInfo`.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **Never blocks capture.** `appendSampleBuffer` runs on the capture queue;
///   when the writer input is not ready the frame is dropped and counted —
///   nothing waits on `finishWriting`. The boundary frame starts the next
///   segment so it begins with a keyframe.
/// - **Never stops GPS.** A writer failure discards the bad segment and calls
///   `onFailure` (the reducer restarts once); ride GPS recording is untouched.
/// - **On-device only.** Files are written under the camera root, excluded from
///   backups, with a protection class that still allows writing while locked
///   after first unlock. Nothing here uploads, links, logs, or transmits a file.
///
/// The real AVFoundation behaviour (segment length, fragment recovery, HEVC
/// support) is a device check (task 31); the seam the coordinator/ring-manager
/// use is unit-tested through `FakeSegmentRecorder`.
@MainActor
final class AssetWriterSegmentRecorder: SegmentRecording {
    var onSegmentFinished: ((SegmentInfo) -> Void)?
    var onFailure: ((SegmentRecorderError) -> Void)?

    private let core: SegmentWriterCore
    private let rideId: UUID
    private var profileName: String = CaptureProfile.standard.name

    init(
        layout: CameraStorageLayout,
        rideId: UUID,
        tuning: RideCameraTuning = RideCameraTuning(),
        fileManager: FileManager = .default
    ) {
        self.rideId = rideId
        core = SegmentWriterCore(
            layout: layout,
            rideId: rideId,
            segmentLength: tuning.segmentLength,
            movieFragmentInterval: tuning.movieFragmentInterval,
            fileManager: fileManager
        )
        core.onFinished = { [weak self] finished in
            Task { @MainActor in self?.deliverFinished(finished) }
        }
        core.onFailure = { [weak self] error in
            Task { @MainActor in self?.onFailure?(error) }
        }
    }

    // MARK: SegmentRecording (Foundation-only seam)

    func begin(profile: CaptureProfile, orientation: CameraMountOrientation) {
        profileName = profile.name
        core.configure(
            videoSettings: Self.videoOutputSettings(profile: profile),
            transform: Self.orientationTransform(orientation)
        )
    }

    func append(_ frame: CameraCaptureFrame) {
        core.noteFrameMetadata(isDiscontinuity: frame.isDiscontinuity)
    }

    func rotate(at boundary: Date) {
        core.rotate(at: boundary)
    }

    func finish() {
        core.finish()
    }

    // MARK: AVFoundation-only pixel path (capture queue)

    /// Append one captured sample buffer. Call on the capture serial queue.
    nonisolated func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        core.appendSampleBuffer(sampleBuffer)
    }

    /// Frames dropped at the writer (not ready) since the recorder began.
    nonisolated var droppedFrameCount: Int { core.droppedFrameCount }

    // MARK: - Private

    private func deliverFinished(_ finished: SegmentWriterCore.FinishedSegment) {
        let segment = SegmentInfo(
            id: UUID(),
            rideId: rideId,
            index: finished.index,
            start: Date(timeIntervalSince1970: finished.startEpoch),
            end: Date(timeIntervalSince1970: finished.endEpoch),
            bytes: finished.bytes,
            profileName: profileName,
            hasAudio: false,
            isPinned: false,
            hasGapBefore: finished.hasGapBefore
        )
        onSegmentFinished?(segment)
    }

    /// The AVFoundation video output settings for a profile. Built on the main
    /// actor where the domain `CaptureProfile` lives; the core stores the opaque
    /// dictionary.
    private static func videoOutputSettings(profile: CaptureProfile) -> [String: Any] {
        let codec: AVVideoCodecType = profile.codec == .hevc ? .hevc : .h264
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: profile.width,
            AVVideoHeightKey: profile.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: profile.averageBitrate,
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0
            ]
        ]
    }

    private static func orientationTransform(_ orientation: CameraMountOrientation) -> CGAffineTransform {
        switch orientation {
        case .landscapeRight: return .identity
        case .landscapeLeft: return CGAffineTransform(rotationAngle: .pi)
        case .portrait: return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: -.pi / 2)
        }
    }
}

/// The lock-guarded `AVAssetWriter` machinery. `nonisolated` so `appendSampleBuffer`
/// runs on the capture queue; the lock serializes it against `configure`/`rotate`/
/// `finish` driven from the main-actor wrapper. `@unchecked Sendable` because all
/// mutable state is accessed only under `lock` (the documented, reviewed exception
/// for the capture hot path; design concurrency note). It traffics only in
/// primitives and AVFoundation types — never the domain value types.
nonisolated final class SegmentWriterCore: @unchecked Sendable {
    /// A finished segment reported as raw numbers; the wrapper maps it to the
    /// domain `SegmentInfo` on the main actor.
    struct FinishedSegment: Sendable {
        let index: Int
        let startEpoch: TimeInterval
        let endEpoch: TimeInterval
        let bytes: Int64
        let hasGapBefore: Bool
    }

    /// Delivered (off the capture queue) when a segment finishes.
    var onFinished: (@Sendable (FinishedSegment) -> Void)?
    /// Delivered (off the capture queue) when the writer fails.
    var onFailure: (@Sendable (SegmentRecorderError) -> Void)?

    private let layout: CameraStorageLayout
    private let rideId: UUID
    private let segmentLength: TimeInterval
    private let movieFragmentInterval: TimeInterval
    private let fileManager: FileManager
    private static let logger = Logger(subsystem: "com.whoosh.app", category: "SegmentRecorder")

    private let lock = NSLock()
    private var videoSettings: [String: Any] = [:]
    private var transform: CGAffineTransform = .identity
    private var segmentIndex = 0
    private var droppedFrames = 0
    private var current: WriterContext?
    private var nextSegmentHasGapBefore = false

    init(
        layout: CameraStorageLayout,
        rideId: UUID,
        segmentLength: TimeInterval,
        movieFragmentInterval: TimeInterval,
        fileManager: FileManager
    ) {
        self.layout = layout
        self.rideId = rideId
        self.segmentLength = segmentLength
        self.movieFragmentInterval = movieFragmentInterval
        self.fileManager = fileManager
        createRingDirectory()
    }

    // MARK: Seam-driven (main-actor wrapper calls, serialized by the lock)

    func configure(videoSettings: [String: Any], transform: CGAffineTransform) {
        lock.lock(); defer { lock.unlock() }
        self.videoSettings = videoSettings
        self.transform = transform
        nextSegmentHasGapBefore = false
    }

    func noteFrameMetadata(isDiscontinuity: Bool) {
        guard isDiscontinuity else { return }
        lock.lock(); defer { lock.unlock() }
        nextSegmentHasGapBefore = true
    }

    func rotate(at boundary: Date) {
        lock.lock()
        let finished = finishCurrentLocked(end: boundary)
        lock.unlock()
        if let finished { onFinished?(finished) }
    }

    func finish() {
        lock.lock()
        let finished = finishCurrentLocked(end: nil)
        lock.unlock()
        if let finished { onFinished?(finished) }
    }

    // MARK: Capture-queue pixel path

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTIME_IS_VALID(pts) else { return }
        let ptsSeconds = CMTimeGetSeconds(pts)
        let wallClock = Date()

        var finishedToEmit: FinishedSegment?
        var failureToEmit: SegmentRecorderError?

        lock.lock()
        if current == nil {
            openWriterLocked(startWall: wallClock)
        }
        if let context = current,
           ptsSeconds - context.startSeconds >= segmentLength {
            finishedToEmit = finishCurrentLocked(end: wallClock)
            openWriterLocked(startWall: wallClock)
        }
        if let writer = current {
            if !writer.input.isReadyForMoreMediaData {
                droppedFrames += 1
            } else {
                if writer.assetWriter.status == .unknown {
                    writer.assetWriter.startWriting()
                    writer.assetWriter.startSession(atSourceTime: pts)
                }
                if writer.assetWriter.status == .failed {
                    current = nil
                    failureToEmit = .writerFailed
                } else {
                    writer.input.append(sampleBuffer)
                    writer.startSeconds = writer.hasStarted ? writer.startSeconds : ptsSeconds
                    writer.hasStarted = true
                    writer.bytesEstimate += Int64(CMSampleBufferGetTotalSampleSize(sampleBuffer))
                }
            }
        }
        lock.unlock()

        if let finishedToEmit { onFinished?(finishedToEmit) }
        if let failureToEmit { onFailure?(failureToEmit) }
    }

    var droppedFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return droppedFrames
    }

    // MARK: - Writer lifecycle (call with the lock held)

    private final class WriterContext {
        let assetWriter: AVAssetWriter
        let input: AVAssetWriterInput
        let url: URL
        let index: Int
        let start: Date
        var startSeconds: Double
        let hasGapBefore: Bool
        var hasStarted: Bool
        var bytesEstimate: Int64

        init(
            assetWriter: AVAssetWriter, input: AVAssetWriterInput, url: URL,
            index: Int, start: Date, startSeconds: Double, hasGapBefore: Bool
        ) {
            self.assetWriter = assetWriter
            self.input = input
            self.url = url
            self.index = index
            self.start = start
            self.startSeconds = startSeconds
            self.hasGapBefore = hasGapBefore
            self.hasStarted = false
            self.bytesEstimate = 0
        }
    }

    private func openWriterLocked(startWall: Date) {
        let index = segmentIndex
        segmentIndex += 1
        let fileName = layout.segmentFileName(index: index, start: startWall)
        let url = layout.ringDirectory(rideId: rideId).appendingPathComponent(fileName)
        removeFileIfPresent(url)

        guard let assetWriter = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            Self.logger.error("Failed to create AVAssetWriter for a segment")
            onFailure?(.fileUnavailable)
            return
        }
        assetWriter.movieFragmentInterval = CMTime(
            seconds: movieFragmentInterval, preferredTimescale: 600
        )

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        input.transform = transform
        if assetWriter.canAdd(input) {
            assetWriter.add(input)
        }

        applyProtection(url)
        excludeFromBackup(url)

        current = WriterContext(
            assetWriter: assetWriter, input: input, url: url, index: index,
            start: startWall, startSeconds: 0, hasGapBefore: nextSegmentHasGapBefore
        )
        nextSegmentHasGapBefore = false
    }

    private func finishCurrentLocked(end: Date?) -> FinishedSegment? {
        guard let context = current else { return nil }
        current = nil

        let endWall = end ?? Date()
        context.input.markAsFinished()
        // Asynchronous finalize — the capture queue never blocks; the movie
        // fragments keep the file playable even if finishWriting never completes.
        context.assetWriter.finishWriting { }

        let bytes = (try? context.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .flatMap { Int64($0) } ?? context.bytesEstimate

        return FinishedSegment(
            index: context.index,
            startEpoch: context.start.timeIntervalSince1970,
            endEpoch: endWall.timeIntervalSince1970,
            bytes: bytes,
            hasGapBefore: context.hasGapBefore
        )
    }

    // MARK: - Files

    private func createRingDirectory() {
        let dir = layout.ringDirectory(rideId: rideId)
        guard !fileManager.fileExists(atPath: dir.path) else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        applyProtection(dir)
        excludeFromBackup(dir)
    }

    private func applyProtection(_ url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func excludeFromBackup(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    private func removeFileIfPresent(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
