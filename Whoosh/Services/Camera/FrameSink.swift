import Foundation

/// The seam a frame source (the capture service, `FakeCameraSource`, or the
/// stretch `FileFrameSource`) offers frames to (rear-camera spec task 11; design
/// "Frame pipeline"). `FramePipeline` is the concrete implementation. Keeping the
/// sink a protocol lets the capture hot path depend only on `offer`/lifecycle,
/// and lets tests drive a pipeline directly.
///
/// `offer(_:)` is called on the capture serial queue and **must never block** on
/// a consumer: it does only a registry check, synchronous rate decisions, and a
/// latest-wins mailbox write per consumer (design backpressure rule). It returns
/// immediately.
protocol FrameSink: Sendable {
    /// The active capture format began; forwarded to consumers off-main.
    nonisolated func start(format: VideoFrame.Format)
    /// Offer one frame. Non-blocking; returns immediately.
    nonisolated func offer(_ frame: VideoFrame)
    /// The capture format ended; forwarded to consumers off-main.
    nonisolated func stop()
}

/// Per-consumer delivery counters exposed for diagnostics and tests
/// (Requirement 4.5; design backpressure rule 5). Plain value type.
nonisolated struct FrameConsumerStats: Equatable, Sendable {
    /// Stable id of the consumer these stats belong to.
    let consumerID: String
    /// Frames offered to this consumer (post registry check, pre rate limit).
    var offered: Int
    /// Frames actually delivered to `consume(_:)`.
    var delivered: Int
    /// Frames dropped because they exceeded the consumer's max frame rate.
    var rateDropped: Int
    /// Frames dropped because the consumer was still busy and a newer frame
    /// replaced the pending one (latest-wins).
    var busyDropped: Int

    init(
        consumerID: String,
        offered: Int = 0,
        delivered: Int = 0,
        rateDropped: Int = 0,
        busyDropped: Int = 0
    ) {
        self.consumerID = consumerID
        self.offered = offered
        self.delivered = delivered
        self.rateDropped = rateDropped
        self.busyDropped = busyDropped
    }
}
