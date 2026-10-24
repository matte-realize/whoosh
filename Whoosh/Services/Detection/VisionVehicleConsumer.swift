import CoreVideo
import Foundation
import ImageIO
import WhooshVision

/// The on-device vehicle detector adapted as a `FrameConsumer` **and** a
/// `HazardDetector` (rear-camera spec task (b), Requirement 4.9; design
/// "HazardDetector seam update"). It owns Teammate B's
/// `WhooshVision.VehicleDetector`, runs its synchronous `detect` on **its own
/// serial queue**, applies the pure `ApproachEstimator` so a far, static car
/// does not alert, and emits `HazardDetection`s through the frozen
/// `HazardDetection`/`onDetection` seam.
///
/// ## Contract it honors (design, hazard-contract.md)
/// - **Never owns capture.** It creates no capture session, requests no
///   camera permission, and writes no video. The camera capture service /
///   camera-permission seam own those; this type only consumes `VideoFrame`s the
///   `FramePipeline` hands it.
/// - **Off the main actor, one frame at a time.** `consume(_:)` runs on the
///   consumer's own serial `DispatchQueue`; the ~10–40 ms synchronous `detect`
///   is fine there because the pipeline awaits us on our own driver, never on the
///   capture queue (so capture/the writer are never delayed).
/// - **Does not retain frames.** The `CVPixelBuffer` is used only inside
///   `consume(_:)`; nothing keeps it past return (backpressure rule 6). The
///   estimator copies out just the normalized box geometry it needs.
/// - **Honest timestamps.** `HazardDetection.timestamp` is the frame's
///   `capturedAt` wall-clock, so near-miss clip windows align with the video.
/// - **Rider-frame hints.** `relativePositionHint` is produced by the estimator
///   in the rider frame (the rear image is mirrored; hazard-contract decision 1).
/// - **Honest about ability.** Detection is experimental; it cannot guarantee
///   detection or delivery.
///
/// `start()`/`stop()` are driven by the `DetectionCoordinator`, which registers
/// and removes this consumer with the `FramePipeline` only while the camera is
/// recording/degraded and rear detection is enabled. The model is loaded once,
/// lazily and asynchronously, on first `start()`; frames that arrive before the
/// model is ready are dropped (the pipeline simply drops newer frames).
///
/// `final class`, `@unchecked Sendable`: all mutable state (`detector`,
/// `estimator`, `onDetection`) is confined to the serial `queue`; `consumerID`
/// and `configuration` are immutable.
nonisolated final class VisionVehicleConsumer: FrameConsumer, HazardDetector, @unchecked Sendable {
    let consumerID = "whoosh.vision.vehicle"
    let configuration: FrameConsumerConfiguration

    /// Delivered on the main actor by contract. Set by the `DetectionCoordinator`.
    /// Guarded by `queue` for writes/reads off the detection path.
    var onDetection: ((HazardDetection) -> Void)? {
        get { queue.sync { _onDetection } }
        set { queue.sync { _onDetection = newValue } }
    }

    private let tuning: VisionTuning
    /// The consumer's own serial queue (high QoS; off the main actor). All model
    /// and estimator access happens here, one frame at a time.
    private let queue = DispatchQueue(label: "whoosh.vision.vehicle", qos: .userInitiated)

    // All of the following are touched only on `queue` (except `onDetection`,
    // which is also set via the `queue.sync` accessor above).
    private var _onDetection: ((HazardDetection) -> Void)?
    private var detector: VehicleDetector?
    private var isLoading = false
    private var active = false
    private var estimator: ApproachEstimator

    /// A factory for the detector so tests can inject a fake loader; defaults to
    /// loading Teammate B's bundled model once (~1 s).
    private let loadDetector: @Sendable () async throws -> VehicleDetector

    init(
        tuning: VisionTuning = VisionTuning(),
        loadDetector: @escaping @Sendable () async throws -> VehicleDetector = {
            try await VehicleDetector.load()
        }
    ) {
        self.tuning = tuning
        self.estimator = ApproachEstimator(tuning: tuning)
        self.loadDetector = loadDetector
        self.configuration = FrameConsumerConfiguration(
            // ≤ 10 fps so the ~10–40 ms synchronous detect() keeps pace; the
            // pipeline drops anything faster (design "Perf expectations").
            maxFramesPerSecond: 10,
            // 4:2:0 bi-planar is the capture default; a hint only.
            preferredPixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            // 720p is plenty: the model sees 320 px (WhooshVision README).
            maxDimensionHint: 1280,
            wantsDiscontinuityReset: true
        )
    }

    // MARK: - HazardDetector

    /// Begin inference. Idempotent. Loads the model once (async) on first call.
    /// The `DetectionCoordinator` registers us with the pipeline separately.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.active = true
            self.estimator.reset()
            self.loadIfNeededLocked()
        }
    }

    /// Stop inference and release temporal state. Idempotent. The coordinator
    /// removes us from the pipeline separately.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.active = false
            self.estimator.reset()
        }
    }

    // MARK: - FrameConsumer

    func pipelineDidStart(format: VideoFrame.Format) {
        queue.async { [weak self] in
            self?.estimator.reset()
        }
    }

    func pipelineDidStop() {
        queue.async { [weak self] in
            self?.estimator.reset()
        }
    }

    /// Process one frame on `queue`. Already off the main actor and serialized by
    /// the pipeline's per-consumer driver; we hop to `queue` to keep all model
    /// state on one thread and to satisfy `VehicleDetector`'s "one serial queue"
    /// contract.
    func consume(_ frame: VideoFrame) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.process(frame)
                continuation.resume()
            }
        }
    }

    // MARK: - Private (all on `queue`)

    private func process(_ frame: VideoFrame) {
        guard active else { return }
        if frame.isDiscontinuity { estimator.reset() }

        loadIfNeededLocked()
        guard let detector else { return }   // model not ready yet ⇒ drop

        let orientation = Self.cgOrientation(from: frame.orientation)
        guard let detected = try? detector.detect(
            in: frame.pixelBuffer,
            orientation: orientation,
            timestamp: frame.presentationTime
        ) else {
            // A model/Vision failure must never crash or stop recording; just
            // skip this frame (design: a consumer handles its own failures).
            return
        }

        let boxes = detected.boxes.map { box in
            ApproachEstimator.Box(
                label: box.label,
                confidence: Double(box.confidence),
                x: Double(box.rect.origin.x),
                y: Double(box.rect.origin.y),
                width: Double(box.rect.size.width),
                height: Double(box.rect.size.height)
            )
        }

        guard let approach = estimator.update(
            boxes: boxes,
            timestamp: frame.presentationTime,
            isDiscontinuity: frame.isDiscontinuity
        ) else { return }

        let detection = HazardDetection(
            timestamp: frame.capturedAt,   // wall-clock, not inference-finish time
            kind: approach.kind,
            confidence: approach.confidence,
            relativePositionHint: approach.relativePositionHint
        )
        let callback = _onDetection
        // Deliver on the main actor by contract.
        if let callback {
            DispatchQueue.main.async { callback(detection) }
        }
    }

    /// Kick off a one-time async model load if we are active and don't have one.
    /// Must be called on `queue`.
    private func loadIfNeededLocked() {
        guard active, detector == nil, !isLoading else { return }
        isLoading = true
        let load = loadDetector
        let queue = self.queue
        Task { [weak self] in
            let loaded = try? await load()
            guard let self else { return }
            queue.async {
                self.isLoading = false
                // Only keep it if we're still active (stop() may have raced).
                if self.active { self.detector = loaded }
            }
        }
    }

    /// Map the framework-free `VideoFrame.DisplayOrientation` to Vision's
    /// `CGImagePropertyOrientation` (the raw values match: 1/3/6/8).
    private static func cgOrientation(from orientation: VideoFrame.DisplayOrientation) -> CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: UInt32(orientation.rawValue)) ?? .up
    }
}
