import Foundation

/// A `FrameConsumer` that records what it receives, for tests, previews, and a
/// diagnostic view (rear-camera spec task 11; design "RecordingFrameStats/test
/// consumer"). It is the counterpart to `FakeCameraSource`: drive the source,
/// then assert on this consumer's recorded frames and lifecycle calls.
///
/// Lives under `Services/Camera/` so previews and the composition root can use
/// it; tests reach it via `@testable import`.
///
/// `consume(_:)` runs off the main actor, one frame at a time, so all recorded
/// state is guarded by a lock. An optional `processingDelay` makes it a
/// controllable **slow consumer** (to exercise the latest-wins busy-drop path)
/// without blocking capture — the delay is an `await`, never a thread sleep.
nonisolated final class RecordingFrameStats: FrameConsumer, @unchecked Sendable {
    let consumerID: String
    let configuration: FrameConsumerConfiguration

    private let stateLock = NSLock()
    private var _receivedSequences: [Int] = []
    private var _receivedPresentationTimes: [TimeInterval] = []
    private var _discontinuitySequences: [Int] = []
    private var _startedFormats: [VideoFrame.Format] = []
    private var _stopCount = 0
    private var _processingDelay: TimeInterval

    init(
        consumerID: String = "test.recorder",
        maxFramesPerSecond: Double = 1_000, // effectively unlimited unless overridden
        wantsDiscontinuityReset: Bool = true,
        processingDelay: TimeInterval = 0
    ) {
        self.consumerID = consumerID
        self.configuration = FrameConsumerConfiguration(
            maxFramesPerSecond: maxFramesPerSecond,
            wantsDiscontinuityReset: wantsDiscontinuityReset
        )
        self._processingDelay = processingDelay
    }

    // MARK: FrameConsumer

    nonisolated func consume(_ frame: VideoFrame) async {
        let delay = currentDelay()
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        stateLock.withLock {
            _receivedSequences.append(frame.sequence)
            _receivedPresentationTimes.append(frame.presentationTime)
            if frame.isDiscontinuity {
                _discontinuitySequences.append(frame.sequence)
            }
        }
    }

    nonisolated func pipelineDidStart(format: VideoFrame.Format) {
        stateLock.withLock { _startedFormats.append(format) }
    }

    nonisolated func pipelineDidStop() {
        stateLock.withLock { _stopCount += 1 }
    }

    // MARK: Scripting / assertions

    /// Change the simulated per-frame processing delay at runtime.
    func setProcessingDelay(_ delay: TimeInterval) {
        stateLock.withLock { _processingDelay = delay }
    }

    private func currentDelay() -> TimeInterval {
        stateLock.withLock { _processingDelay }
    }

    /// Sequence numbers of the frames delivered to `consume`, in order.
    var receivedSequences: [Int] {
        stateLock.lock(); defer { stateLock.unlock() }
        return _receivedSequences
    }

    /// Presentation times of the delivered frames, in order.
    var receivedPresentationTimes: [TimeInterval] {
        stateLock.lock(); defer { stateLock.unlock() }
        return _receivedPresentationTimes
    }

    /// Count of frames delivered to `consume`.
    var deliveredCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _receivedSequences.count
    }

    /// Sequence numbers of frames that arrived flagged as a discontinuity.
    var discontinuitySequences: [Int] {
        stateLock.lock(); defer { stateLock.unlock() }
        return _discontinuitySequences
    }

    /// Formats seen via `pipelineDidStart`.
    var startedFormats: [VideoFrame.Format] {
        stateLock.lock(); defer { stateLock.unlock() }
        return _startedFormats
    }

    /// How many times `pipelineDidStop` was called.
    var stopCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _stopCount
    }
}
