import CoreVideo
import Foundation
import Testing
@testable import Whoosh

/// Tests for the `FramePipeline` and the consumer contract (rear-camera spec
/// task 11, Requirement 4; design "FP-1…8"). One area per design row:
///
/// - FP-1 zero-consumer no-op
/// - FP-2 slow consumer drops older frames (latest-wins)
/// - FP-3 two consumers independent
/// - FP-4 add/remove while running
/// - FP-5 busy-drop counts
/// - FP-6 ≤ 1 in-flight + 1 pending retained per consumer
/// - FP-7 discontinuity flag after restart / on fresh registration
/// - FP-8 fake-source ordering
///
/// The pipeline runs consumers on their own driver tasks off the main actor;
/// `quiesce()` gives deterministic drain points without real sleeps.
struct FramePipelineTests {
    /// Yields until `condition` holds. Consumers and lifecycle callbacks run on
    /// detached tasks, so tests wait for the effect rather than guessing how
    /// many yields it takes; bounded so a real bug fails instead of hanging.
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func makeFormat() -> VideoFrame.Format {
        VideoFrame.Format(width: 64, height: 48, pixelFormat: kCVPixelFormatType_32BGRA, framesPerSecond: 30)
    }

    private func makeFrame(
        seq: Int,
        time: TimeInterval,
        discontinuity: Bool = false
    ) -> VideoFrame {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
        return VideoFrame(
            pixelBuffer: buffer!,
            presentationTime: time,
            capturedAt: Date(timeIntervalSince1970: time),
            orientation: .up,
            sequence: seq,
            isDiscontinuity: discontinuity,
            format: makeFormat()
        )
    }

    // MARK: FP-1 — no consumers ⇒ zero per-frame work

    @Test func fp1_zeroConsumersIsNoOp() async {
        let pipeline = FramePipeline()
        pipeline.start(format: makeFormat())
        // Offering with no consumers must return immediately and record nothing.
        for i in 0..<100 {
            pipeline.offer(makeFrame(seq: i, time: Double(i) / 30.0))
        }
        #expect(pipeline.consumerCount == 0)
        #expect(pipeline.stats.isEmpty)
        await pipeline.quiesce() // returns immediately (no entries)
        pipeline.stop()
    }

    // MARK: FP-8 — fake source ordering; every frame delivered when unlimited

    @Test func fp8_fakeSourceOrderingAllDelivered() async {
        let pipeline = FramePipeline()
        let consumer = RecordingFrameStats(consumerID: "c", maxFramesPerSecond: 10_000)
        pipeline.register(consumer)

        let source = FakeCameraSource(sink: pipeline, framesPerSecond: 30)
        source.start()
        // Pace like a real camera (one frame per interval): a back-to-back
        // synchronous burst would legitimately busy-drop in the latest-wins slot.
        for i in 0..<10 {
            source.emit(presentationTime: Double(i) / 30.0)
            await pipeline.quiesce()
        }

        // Delivered in offer order (monotonic sequence), none reordered.
        #expect(consumer.receivedSequences == Array(0..<10))
        source.stop()
    }

    // MARK: FP-2 / FP-5 / FP-6 — slow consumer: latest-wins, busy-drops counted,
    // bounded retention.

    @Test func fp2_slowConsumerDropsOlderFrames() async {
        let pipeline = FramePipeline()
        // Slow: ~20 ms per frame, unlimited rate so drops are busy-drops only.
        let consumer = RecordingFrameStats(
            consumerID: "slow",
            maxFramesPerSecond: 10_000,
            processingDelay: 0.02
        )
        pipeline.register(consumer)
        let source = FakeCameraSource(sink: pipeline)
        source.start()

        // Burst many frames faster than the consumer can process.
        for i in 0..<50 {
            source.emit(presentationTime: Double(i) / 30.0)
        }
        await pipeline.quiesce()

        let stats = pipeline.stats.first { $0.consumerID == "slow" }!
        // Everything offered is accounted for: delivered + rateDropped + busyDropped.
        #expect(stats.offered == 50)
        #expect(stats.rateDropped == 0) // rate is effectively unlimited
        #expect(stats.delivered + stats.busyDropped == 50)
        // A slow consumer must have skipped some frames (latest-wins).
        #expect(stats.busyDropped > 0)
        #expect(stats.delivered < 50)
        // The last offered frame is always eventually delivered (latest-wins
        // keeps the newest), so the final sequence is present.
        #expect(consumer.receivedSequences.last == 49)
        // Delivered sequences are strictly increasing (older frames dropped, not
        // reordered).
        #expect(consumer.receivedSequences == consumer.receivedSequences.sorted())
        source.stop()
    }

    // MARK: FP-3 — two consumers are independent (one slow, one fast)

    @Test func fp3_twoConsumersIndependent() async {
        let pipeline = FramePipeline()
        let fast = RecordingFrameStats(consumerID: "fast", maxFramesPerSecond: 10_000)
        let slow = RecordingFrameStats(consumerID: "slow", maxFramesPerSecond: 10_000, processingDelay: 0.02)
        pipeline.register(fast)
        pipeline.register(slow)

        let source = FakeCameraSource(sink: pipeline)
        source.start()
        // Pace like a real camera: wait until the fast consumer has taken each
        // frame before the next arrives. The slow one (20 ms per frame) falls
        // behind and busy-drops; it must never hold the fast one back.
        for i in 0..<30 {
            source.emit(presentationTime: Double(i) / 30.0)
            await eventually { fast.receivedSequences.count == i + 1 }
        }
        await pipeline.quiesce()

        // The fast consumer, unblocked by the slow one, receives every frame.
        #expect(fast.receivedSequences == Array(0..<30))
        // The slow consumer dropped some but kept the latest.
        #expect(slow.deliveredCount <= 30)
        #expect(slow.receivedSequences.last == 29)
        source.stop()
    }

    // MARK: FP-4 — add/remove while running without interrupting others

    @Test func fp4_addAndRemoveWhileRunning() async {
        let pipeline = FramePipeline()
        let a = RecordingFrameStats(consumerID: "a", maxFramesPerSecond: 10_000)
        pipeline.register(a)
        let source = FakeCameraSource(sink: pipeline)
        source.start()

        source.emit(presentationTime: 0)
        await pipeline.quiesce()
        #expect(a.deliveredCount == 1)

        // Register b mid-run; it should start receiving subsequent frames.
        let b = RecordingFrameStats(consumerID: "b", maxFramesPerSecond: 10_000)
        pipeline.register(b)
        source.emit(presentationTime: 1.0)
        await pipeline.quiesce()
        #expect(a.deliveredCount == 2)
        #expect(b.deliveredCount == 1)

        // Remove a mid-run; only b receives the next frame, and a got a stop.
        pipeline.remove(consumerID: "a")
        // Give the stop notification task a chance to run.
        await Task.yield()
        source.emit(presentationTime: 2.0)
        await pipeline.quiesce()
        #expect(a.deliveredCount == 2) // unchanged after removal
        #expect(b.deliveredCount == 2)
        #expect(pipeline.consumerCount == 1)
        source.stop()
    }

    // MARK: FP-5 — rate limiting drops are counted separately from busy-drops

    @Test func fp5_rateLimitingCounts() async {
        let pipeline = FramePipeline()
        // Fast consumer, but capped at 10 fps. Capture at 30 fps ⇒ ~2/3 rate-dropped.
        let consumer = RecordingFrameStats(consumerID: "capped", maxFramesPerSecond: 10)
        pipeline.register(consumer)
        let source = FakeCameraSource(sink: pipeline, framesPerSecond: 30)
        source.start()
        // Paced like a real camera (3 s at 30 fps) so every drop is a rate drop;
        // a synchronous burst would add scheduling-dependent busy-drops.
        for i in 0..<90 {
            source.emit(presentationTime: Double(i) / 30.0)
            await pipeline.quiesce()
        }

        let stats = pipeline.stats.first { $0.consumerID == "capped" }!
        #expect(stats.offered == 90)
        #expect(stats.busyDropped == 0)
        #expect(stats.delivered + stats.rateDropped == 90)
        // 10 fps over 3 s: every third frame.
        #expect(stats.delivered == 30)
        source.stop()
    }

    // MARK: FP-6 — bounded retention: never more than 1 in-flight + 1 pending

    @Test func fp6_boundedRetention() async {
        let pipeline = FramePipeline()
        let slow = RecordingFrameStats(consumerID: "slow", maxFramesPerSecond: 10_000, processingDelay: 0.03)
        pipeline.register(slow)
        let source = FakeCameraSource(sink: pipeline)
        source.start()
        // Flood 100 frames while the consumer is slow.
        for i in 0..<100 {
            source.emit(presentationTime: Double(i) / 30.0)
        }
        await pipeline.quiesce()
        let stats = pipeline.stats.first { $0.consumerID == "slow" }!
        // With a single-slot mailbox, delivered is far below 100 and the
        // difference is entirely busy-drops (no unbounded queueing).
        #expect(stats.delivered + stats.busyDropped == 100)
        #expect(stats.delivered < 100)
        source.stop()
    }

    // MARK: FP-7 — discontinuity flag: fresh registration + explicit gap

    @Test func fp7_discontinuityOnFirstFrameAndAfterGap() async {
        let pipeline = FramePipeline()
        let consumer = RecordingFrameStats(consumerID: "d", maxFramesPerSecond: 10_000)
        pipeline.register(consumer)
        let source = FakeCameraSource(sink: pipeline)
        source.start()

        // First delivered frame is flagged as a discontinuity (fresh consumer).
        source.emit(presentationTime: 0.0)
        await pipeline.quiesce()
        #expect(consumer.discontinuitySequences == [0])

        // Steady frames are not discontinuities.
        source.emit(presentationTime: 1.0 / 30.0)
        source.emit(presentationTime: 2.0 / 30.0)
        await pipeline.quiesce()
        #expect(consumer.discontinuitySequences == [0])

        // A large gap (> 1 s) flags the next frame as a discontinuity.
        source.emit(presentationTime: 5.0)
        await pipeline.quiesce()
        #expect(consumer.discontinuitySequences.contains(3))
        source.stop()
    }

    // MARK: lifecycle — start/stop forwarded to consumers

    @Test func lifecycleForwardedToConsumers() async {
        let pipeline = FramePipeline()
        let consumer = RecordingFrameStats(consumerID: "life")
        pipeline.register(consumer)
        pipeline.start(format: makeFormat())
        await eventually { consumer.startedFormats.count == 1 }
        #expect(consumer.startedFormats.count == 1)
        #expect(consumer.startedFormats.first?.width == 64)

        pipeline.stop()
        await eventually { consumer.stopCount >= 1 }
        #expect(consumer.stopCount >= 1)
    }

    // MARK: registration before start still delivers once started

    @Test func offerBeforeStartStillFansOut() async {
        // The pipeline does not require start() before offer(); offering frames
        // directly (as a source would) still fans out to registered consumers.
        let pipeline = FramePipeline()
        let consumer = RecordingFrameStats(consumerID: "x", maxFramesPerSecond: 10_000)
        pipeline.register(consumer)
        pipeline.offer(makeFrame(seq: 0, time: 0))
        await pipeline.quiesce()
        #expect(consumer.deliveredCount == 1)
    }
}
