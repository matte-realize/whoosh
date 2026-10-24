import Foundation

/// The concrete frame pipeline (rear-camera spec task 11, Requirement 4;
/// design "Frame pipeline and the consumer contract"). It fans each
/// `VideoFrame` out to zero or more registered `FrameConsumer`s with a
/// **single-slot, latest-wins** mailbox per consumer, rate-limited by the pure
/// `FrameDropPolicy`, and **never** awaits a consumer on the capture path.
///
/// ## Threads and backpressure (normative, design "Data flow and threads")
/// - `offer(_:)` runs on the capture serial queue. It does only: a registry
///   check (empty ⇒ return immediately, Requirement 4.2), a synchronous
///   `FrameDropPolicy` decision per consumer, and a latest-wins mailbox write.
///   It never blocks on a consumer; capture and the segment writer are never
///   delayed (Requirement 4.4).
/// - Each consumer has its own **driver** `Task` (off the main actor). The
///   driver loops: take the latest frame from the mailbox → `await consume` →
///   repeat. A newer frame replaces a pending one (the replaced frame is a
///   busy-drop); at most `1 in-flight + 1 pending` frames are retained per
///   consumer (Requirement 4.6).
/// - Registration/removal is safe at any time; a newly registered consumer's
///   first delivered frame carries the discontinuity flag (Requirement 4.7,
///   4.8, backpressure rule 6).
///
/// ## Swift 6
/// `VideoFrame` is `@unchecked Sendable` (read-only pixel buffer; see its doc).
/// The registry and each mailbox are guarded by an `NSLock`; the pipeline is a
/// `final class` marked `@unchecked Sendable` because all mutable state is
/// lock-protected and the driver tasks are non-isolated (off-main).
nonisolated final class FramePipeline: FrameSink, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: ConsumerEntry] = [:]
    private var currentFormat: VideoFrame.Format?
    private var isStarted = false

    init() {}

    // MARK: - Registration

    /// Register a consumer. Safe while recording. If the pipeline is already
    /// started the consumer is told via `pipelineDidStart(format:)` off-main and
    /// its first delivered frame will be a discontinuity. Re-registering the same
    /// `consumerID` replaces the previous entry.
    func register(_ consumer: FrameConsumer) {
        lock.lock()
        if let existing = entries[consumer.consumerID] {
            existing.shutdown()
            entries[consumer.consumerID] = nil
        }
        let entry = ConsumerEntry(consumer: consumer)
        entries[consumer.consumerID] = entry
        let startedFormat = isStarted ? currentFormat : nil
        lock.unlock()

        entry.startDriver()
        if let format = startedFormat {
            entry.notifyStart(format: format)
        }
    }

    /// Remove a consumer by id. Safe while recording. The consumer's driver is
    /// stopped and `pipelineDidStop()` is delivered off-main. Does nothing if the
    /// id is not registered.
    func remove(consumerID: String) {
        lock.lock()
        let entry = entries[consumerID]
        entries[consumerID] = nil
        lock.unlock()

        entry?.shutdown()
    }

    /// Current per-consumer stats snapshot (diagnostics/tests).
    var stats: [FrameConsumerStats] {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.map { $0.statsSnapshot() }
    }

    /// Number of registered consumers.
    var consumerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - FrameSink

    func start(format: VideoFrame.Format) {
        lock.lock()
        isStarted = true
        currentFormat = format
        let current = Array(entries.values)
        lock.unlock()

        for entry in current {
            entry.notifyStart(format: format)
        }
    }

    /// Offer one frame. **Non-blocking.** Registry-empty ⇒ immediate return with
    /// no per-frame work (Requirement 4.2).
    func offer(_ frame: VideoFrame) {
        lock.lock()
        if entries.isEmpty {
            lock.unlock()
            return
        }
        // Decide and enqueue under the lock (cheap, no awaiting). Collect the
        // drivers to wake outside the lock.
        var toWake: [ConsumerEntry] = []
        for entry in entries.values {
            if entry.consider(frame) {
                toWake.append(entry)
            }
        }
        lock.unlock()

        for entry in toWake {
            entry.wake()
        }
    }

    func stop() {
        lock.lock()
        isStarted = false
        currentFormat = nil
        let current = Array(entries.values)
        lock.unlock()

        for entry in current {
            entry.notifyStop()
        }
    }

    // MARK: - Test support

    /// Await until every registered consumer has drained its mailbox (no pending
    /// or in-flight frame). Deterministic quiescence for tests; polls the
    /// lock-protected state off the capture path. Not used in production.
    func quiesce() async {
        while true {
            let busy = lock.withLock {
                entries.values.contains { $0.isBusy() }
            }
            if !busy { return }
            await Task.yield()
        }
    }
}

// MARK: - ConsumerEntry

/// One consumer's registry slot: its single-slot mailbox, rate-limit baseline,
/// stats, and driver task. All mutable state is guarded by `stateLock`; the
/// `FramePipeline` calls `consider`/`wake` from the capture path and
/// `startDriver`/`shutdown`/`notify*` from registration/lifecycle.
nonisolated private final class ConsumerEntry: @unchecked Sendable {
    private let consumer: FrameConsumer
    private let maxFps: Double
    private let wantsDiscontinuityReset: Bool

    private let stateLock = NSLock()
    // Mailbox: the single pending frame (latest-wins), or nil.
    private var pending: VideoFrame?
    // A frame is currently being processed by the driver.
    private var inFlight = false
    // The consumer has not yet received any frame (first frame ⇒ discontinuity).
    private var isFirstFrame = true
    private var lastDeliveredTime: TimeInterval?
    private var stats: FrameConsumerStats

    // Driver signaling.
    private var waiter: CheckedContinuation<Void, Never>?
    private var isShutdown = false
    private var driver: Task<Void, Never>?

    init(consumer: FrameConsumer) {
        self.consumer = consumer
        self.maxFps = consumer.configuration.maxFramesPerSecond
        self.wantsDiscontinuityReset = consumer.configuration.wantsDiscontinuityReset
        self.stats = FrameConsumerStats(consumerID: consumer.consumerID)
    }

    // MARK: Capture-path (non-blocking)

    /// Apply the rate policy and, if the frame passes, place it in the mailbox
    /// (latest-wins). Returns `true` if the driver should be woken. Called under
    /// the pipeline lock; takes its own state lock for the mailbox.
    func consider(_ frame: VideoFrame) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isShutdown else { return false }

        stats.offered += 1

        let decision = FrameDropPolicy.decide(
            frameTime: frame.presentationTime,
            lastDeliveredTime: lastDeliveredTime,
            maxFramesPerSecond: maxFps
        )
        guard decision.shouldDeliver else {
            stats.rateDropped += 1
            return false
        }

        // This frame will be delivered; advance the rate baseline now so the
        // next offer measures its interval from here (even while this one is
        // still pending/in-flight).
        lastDeliveredTime = frame.presentationTime

        // Decide the discontinuity flag the consumer should see.
        var outgoing = frame
        let needsDiscontinuity = (isFirstFrame || decision.isDiscontinuity)
            && wantsDiscontinuityReset
        if needsDiscontinuity && !frame.isDiscontinuity {
            outgoing = frame.withDiscontinuity()
        }
        isFirstFrame = false

        // Latest-wins: replacing a pending frame is a busy-drop.
        if pending != nil {
            stats.busyDropped += 1
        }
        pending = outgoing

        // Wake only if the driver is idle (not currently processing and parked
        // on the waiter). If inFlight, the driver will pick up the new pending
        // when it finishes.
        return waiter != nil
    }

    func wake() {
        stateLock.lock()
        let cont = waiter
        waiter = nil
        stateLock.unlock()
        cont?.resume()
    }

    // MARK: Lifecycle

    func startDriver() {
        stateLock.lock()
        guard driver == nil, !isShutdown else { stateLock.unlock(); return }
        stateLock.unlock()

        driver = Task.detached { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while true {
            let frame: VideoFrame? = nextFrame()
            guard let frame else {
                if await parkOrExit() { return }
                continue
            }
            await consumer.consume(frame)
            finishInFlight()
        }
    }

    /// Take the pending frame (marking it in-flight), or `nil` if none.
    private func nextFrame() -> VideoFrame? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isShutdown else { return nil }
        guard let frame = pending else { return nil }
        pending = nil
        inFlight = true
        stats.delivered += 1
        return frame
    }

    private func finishInFlight() {
        stateLock.lock()
        inFlight = false
        stateLock.unlock()
    }

    /// Park the driver until woken, or return `true` to exit (shutdown).
    private func parkOrExit() async -> Bool {
        if Task.isCancelled { return true }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stateLock.lock()
            if isShutdown {
                stateLock.unlock()
                cont.resume()
                return
            }
            // A frame may have arrived between the nextFrame() check and here.
            if pending != nil {
                stateLock.unlock()
                cont.resume()
                return
            }
            waiter = cont
            stateLock.unlock()
        }
        return stateLock.withLock { isShutdown }
    }

    func shutdown() {
        stateLock.lock()
        guard !isShutdown else { stateLock.unlock(); return }
        isShutdown = true
        pending = nil
        let cont = waiter
        waiter = nil
        let task = driver
        stateLock.unlock()

        cont?.resume()
        task?.cancel()
        notifyStop()
    }

    func isBusy() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pending != nil || inFlight
    }

    func statsSnapshot() -> FrameConsumerStats {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stats
    }

    // MARK: Lifecycle notifications (off-main)

    func notifyStart(format: VideoFrame.Format) {
        let consumer = self.consumer
        Task.detached { consumer.pipelineDidStart(format: format) }
    }

    private var didNotifyStop = false
    func notifyStop() {
        stateLock.lock()
        if didNotifyStop { stateLock.unlock(); return }
        didNotifyStop = true
        stateLock.unlock()
        let consumer = self.consumer
        Task.detached { consumer.pipelineDidStop() }
    }
}

private extension VideoFrame {
    /// A copy of this frame with the discontinuity flag set (used when a freshly
    /// registered consumer, or one resuming after a gap, should reset temporal
    /// state). The pixel buffer reference is shared (read-only by contract).
    nonisolated func withDiscontinuity() -> VideoFrame {
        VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: presentationTime,
            capturedAt: capturedAt,
            orientation: orientation,
            sequence: sequence,
            isDiscontinuity: true,
            format: format
        )
    }
}
