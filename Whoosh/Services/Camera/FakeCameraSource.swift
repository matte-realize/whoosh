import CoreVideo
import Foundation

/// A scriptable frame source for tests and SwiftUI previews (rear-camera spec
/// task 11, Requirement 4.10; design "FakeCameraSource"). It emits synthetic
/// `VideoFrame`s into a `FrameSink` (normally a `FramePipeline`) **on command**
/// and at a **scripted rate**, so the pipeline, the consumer contract, and
/// Teammate B's detector can be exercised without a camera.
///
/// Lives under `Services/Camera/` (not the test target) so previews, the
/// composition root, and Teammate B's own harness can inject it; tests reach it
/// via `@testable import`.
///
/// It creates small real `CVPixelBuffer`s so a consumer that inspects the buffer
/// has something valid to read. The buffers are read-only by the `VideoFrame`
/// contract.
nonisolated final class FakeCameraSource: @unchecked Sendable {
    /// The sink frames are offered to (set at construction or later).
    private let sink: FrameSink
    private let format: VideoFrame.Format
    private let orientation: VideoFrame.DisplayOrientation

    private let stateLock = NSLock()
    private var sequence = 0
    private var started = false

    /// - Parameters:
    ///   - sink: where frames are offered (a `FramePipeline`).
    ///   - width/height: synthetic buffer size (kept small for tests).
    ///   - framesPerSecond: the nominal capture rate reported in the format.
    ///   - orientation: the display orientation stamped on every frame.
    init(
        sink: FrameSink,
        width: Int = 64,
        height: Int = 48,
        framesPerSecond: Int = 30,
        orientation: VideoFrame.DisplayOrientation = .up
    ) {
        self.sink = sink
        self.format = VideoFrame.Format(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            framesPerSecond: framesPerSecond
        )
        self.orientation = orientation
    }

    /// Start the session (forwards `start(format:)` to the sink). Idempotent.
    func start() {
        stateLock.lock()
        let wasStarted = started
        started = true
        stateLock.unlock()
        if !wasStarted { sink.start(format: format) }
    }

    /// Stop the session (forwards `stop()` to the sink). Idempotent.
    func stop() {
        stateLock.lock()
        let wasStarted = started
        started = false
        stateLock.unlock()
        if wasStarted { sink.stop() }
    }

    /// Emit exactly one synthetic frame with the given presentation time
    /// (seconds) and optional wall-clock capture time and discontinuity flag.
    /// Returns the sequence number stamped on the frame.
    @discardableResult
    func emit(
        presentationTime: TimeInterval,
        capturedAt: Date = Date(),
        isDiscontinuity: Bool = false
    ) -> Int {
        stateLock.lock()
        let seq = sequence
        sequence += 1
        stateLock.unlock()

        let frame = VideoFrame(
            pixelBuffer: Self.makePixelBuffer(width: format.width, height: format.height),
            presentationTime: presentationTime,
            capturedAt: capturedAt,
            orientation: orientation,
            sequence: seq,
            isDiscontinuity: isDiscontinuity,
            format: format
        )
        sink.offer(frame)
        return seq
    }

    /// Emit `count` frames at the scripted `framesPerSecond` (the format's rate
    /// unless overridden), starting at `startTime` seconds. Each frame's
    /// `capturedAt` is derived from `startDate` + the presentation offset.
    func emitBurst(
        count: Int,
        startTime: TimeInterval = 0,
        startDate: Date = Date(timeIntervalSince1970: 0),
        framesPerSecond: Int? = nil
    ) {
        let fps = framesPerSecond ?? format.framesPerSecond
        let interval = fps > 0 ? 1.0 / Double(fps) : 0
        for i in 0..<count {
            let offset = Double(i) * interval
            emit(
                presentationTime: startTime + offset,
                capturedAt: startDate.addingTimeInterval(offset)
            )
        }
    }

    // MARK: - Synthetic buffer

    /// Create a small zeroed BGRA pixel buffer. Force-unwrap is acceptable in
    /// this test/preview support type (a failure here is a programming error).
    private static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            fatalError("FakeCameraSource could not create a synthetic pixel buffer (status \(status))")
        }
        return buffer
    }
}
