import Foundation
import Observation

/// The composition that actually **runs** rear-vehicle detection during a ride
/// (rear-camera spec tasks 14 + B1 glue; design "HazardDetector seam update").
///
/// Everything it needs already exists but was never connected: the camera
/// (`CameraRecordingCoordinator`) builds a shared `FramePipeline` and records,
/// and the pure `DetectionCoordinator` already routes `HazardDetection`s to the
/// alert gate, near-miss policy, and clip pinning. This type wires the missing
/// seam: it owns the real `VisionVehicleConsumer` (Teammate B's
/// `VehicleDetector` as a `FrameConsumer`), loads the CoreML model **once**
/// (async) when rear camera recording is enabled — not per ride — and drives the
/// `DetectionCoordinator`'s register/start and remove/stop from the live camera
/// recording state.
///
/// ## Lifecycle
/// - `modelPreloadIfNeeded()` — called when rear camera recording is enabled, it
///   starts the one-time async model load. Safe to call repeatedly.
/// - `cameraStateChanged(_:)` — the `CameraRecordingCoordinator` calls this on
///   every state change. While the camera is `recording`/`degraded` the detector
///   is registered on the shared pipeline and started; on pause, interruption,
///   stop, failure, or ride end it is removed and stopped. Detection **never**
///   blocks capture or recording (the latest-wins pipeline guarantees this).
/// - `beginRide()` / `endRide()` — reset per-ride counters / tear down.
///
/// ## Observable state
/// `detectionState` drives the ride-screen camera chip (on / model loading /
/// unavailable / off). It is honest: detection is experimental and cannot
/// guarantee detection or delivery; the chip only reports readiness.
///
/// ## Events
/// `onDetection` / `detectionEvents()` forward the coordinator's detection hook
/// so the parallel `NearMissRecorder` can subscribe without this type depending
/// on it. Nothing here touches the network; footage never leaves the device.
///
/// `@Observable`, `@MainActor` — the chip observes `detectionState`; the model
/// loads and inference run off the main actor inside `VisionVehicleConsumer`.
@Observable
@MainActor
final class RideDetectionCoordinator {
    /// The current detector readiness for the ride-screen chip.
    private(set) var detectionState: DetectionState = .off

    /// Forwarded from the `DetectionCoordinator`: fired for every handled
    /// detection so a near-miss logger can subscribe. Set by the caller.
    @ObservationIgnored var onDetection: ((HazardDetection) -> Void)? {
        didSet { coordinator.onDetection = onDetection }
    }

    @ObservationIgnored private let consumer: VisionVehicleConsumer
    @ObservationIgnored private let coordinator: DetectionCoordinator
    /// Whether rear detection is allowed to run at all (rear camera recording on).
    @ObservationIgnored private let isEnabled: () -> Bool
    /// The latest camera state, read by the coordinator's provider.
    @ObservationIgnored private var cameraState: CameraRecordingState = .off
    /// The last model-load state reported by the consumer.
    @ObservationIgnored private var modelState: VisionVehicleConsumer.ModelLoadState?
    @ObservationIgnored private var didStartPreload = false

    /// Build the running detection stack. The `makeCoordinator` factory receives
    /// the live providers this type owns — the camera recording state and
    /// whether rear detection is enabled — so the injected `DetectionCoordinator`
    /// reads *this* coordinator's state without an init-ordering cycle. The
    /// composition root (`AppEnvironment`) supplies a factory that fills in the
    /// remaining seams (alert manager, near-miss, clip pinning) over the shared
    /// `FramePipeline`.
    init(
        consumer: VisionVehicleConsumer,
        isEnabled: @escaping () -> Bool,
        makeCoordinator: (
            _ detector: VisionVehicleConsumer,
            _ cameraStateProvider: @escaping () -> CameraRecordingState,
            _ isDetectionEnabled: @escaping () -> Bool
        ) -> DetectionCoordinator
    ) {
        self.consumer = consumer
        self.isEnabled = isEnabled

        // A box so the provider closures can read the live state captured below
        // without referencing `self` before it is fully initialized.
        let stateBox = StateBox()
        self.coordinator = makeCoordinator(
            consumer,
            { stateBox.cameraState },
            { stateBox.isEnabled }
        )
        self.stateBox = stateBox
        stateBox.isEnabled = isEnabled()

        // Seed from the consumer's current model state in case the model was
        // already loaded (preloaded when the feature was enabled) before this
        // per-ride coordinator was built, so the chip isn't stuck on "loading".
        self.modelState = consumer.currentModelState

        // Mirror the model's one-time load progress into the observable chip
        // state (delivered on the main actor by the consumer's contract).
        consumer.onModelStateChange = { [weak self] state in
            self?.modelState = state
            self?.recomputeState()
        }
    }

    /// Mutable, main-actor-only holder the `DetectionCoordinator`'s provider
    /// closures read. Kept tiny and private so the providers never capture
    /// `self` (which does not exist yet at `makeCoordinator` time).
    @MainActor private final class StateBox {
        var cameraState: CameraRecordingState = .off
        var isEnabled = false
    }
    @ObservationIgnored private let stateBox: StateBox

    /// Forward a detection-events stream for near-miss logging.
    func detectionEvents() -> AsyncStream<HazardDetection> {
        coordinator.detectionEvents()
    }

    // MARK: - Lifecycle

    /// Begin a ride: reset per-ride counters and evaluate whether to run.
    func beginRide() {
        stateBox.isEnabled = isEnabled()
        coordinator.beginRide()
        recomputeState()
    }

    /// The camera recording state changed — register/start or remove/stop the
    /// detector to match (recording/degraded ⇒ run; anything else ⇒ off). Never
    /// blocks capture.
    func cameraStateChanged(_ state: CameraRecordingState) {
        stateBox.cameraState = state
        stateBox.isEnabled = isEnabled()
        coordinator.refresh()
        recomputeState()
    }

    /// Tear down at ride end / feature disable: stop and unregister the detector.
    func endRide() {
        coordinator.endRide()
        stateBox.cameraState = .off
        recomputeState()
    }

    /// Start the one-time async model load when rear camera recording is enabled.
    /// The consumer loads lazily on first `start()`, but preloading here means
    /// the model is warm before the first ride. Idempotent.
    func modelPreloadIfNeeded() {
        guard isEnabled(), !didStartPreload else { return }
        didStartPreload = true
        // `start()` triggers the one-time async load on the consumer's queue and
        // reports `.loading` → `.ready`/`.unavailable` back through
        // `onModelStateChange`. The coordinator registers the consumer with the
        // pipeline only while recording, so a preload before a ride only loads
        // the model; no frames flow until recording starts.
        consumer.start()
        recomputeState()
    }

    // MARK: - Derived chip state

    /// Map the camera state + model-load state to the chip's `DetectionState`.
    private func recomputeState() {
        guard isEnabled() else {
            detectionState = .off
            return
        }
        guard stateBox.cameraState.isRecording else {
            // Not recording: detection is not running. If the model failed to
            // load, keep surfacing that so the rider is not misled into thinking
            // detection will resume.
            detectionState = modelState == .unavailable ? .unavailable : .off
            return
        }
        switch modelState {
        case .ready:
            detectionState = .on
        case .unavailable:
            detectionState = .unavailable
        case .loading, .none:
            detectionState = .loading
        }
    }
}
