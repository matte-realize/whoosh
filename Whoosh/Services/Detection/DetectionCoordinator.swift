import Foundation

/// Routes `HazardDetection`s from a `HazardDetector` to the alert, near-miss,
/// and clip-pin seams, and owns when the detector is registered with the frame
/// pipeline (rear-camera spec task 14, Requirements 4.9, 15.1–15.5; design
/// "Detection events and near-miss records" and "HazardDetector seam update").
///
/// It does **not** own the camera, the model, or the pipeline's capture side; it
/// only decides, per the explicit camera state and the rear-detection toggle,
/// whether the detector should be running, and what to do with each detection:
///
/// 1. **Alert** — normal mode: `RearAlertGate` (only while `recording` and
///    moving > the threshold) decides, except in **demo mode**, which bypasses
///    the gate (demo-mode design). A fired alert honors
///    `RideCameraTuning.rearVehicleAlertCooldown` so a burst collapses to one
///    cue. The alert is an experimental cue; it cannot guarantee detection or
///    delivery.
/// 2. **Near-miss event** — `NearMissPolicy` decides whether the detection
///    becomes a local `NearMissEvent` (and, if eligible, a pinned clip). The
///    event carries the nearest accepted route coordinate (looked up by the
///    injected provider); the local clip id links a pin only when one succeeds.
/// 3. **Clip** — on `recordAndPin`, the injected `pinDetectionClip` seam pins a
///    detection clip from the ring buffer and returns its local id (no upload;
///    footage never leaves the device).
///
/// ## Registration lifecycle
/// `refresh()` (or any state/toggle change through the setters) registers the
/// detector with the `FramePipeline` **and** calls `detector.start()` only while
/// the camera is `recording`/`degraded` **and** rear detection is enabled; it
/// removes the detector and calls `detector.stop()` otherwise. If the detector
/// also conforms to `FrameConsumer` (the real `VisionVehicleConsumer`) it is
/// registered as a pipeline consumer; a non-consumer detector (the fake) is only
/// started/stopped. The `NoopDetector` stays inert — it never emits, so no
/// registration has any effect.
///
/// `@MainActor` (design: the coordinator is main-actor; `onDetection` is
/// delivered on the main actor). Pure decisions live in `RearAlertGate`,
/// `NearMissPolicy`, and `AlertCooldown`; this type only sequences them and
/// holds the small amount of per-ride counters.
@MainActor
final class DetectionCoordinator {
    /// A looked-up route coordinate for a detection instant.
    typealias RouteCoordinate = (latitude: Double, longitude: Double)

    private let detector: HazardDetector
    private let pipeline: FramePipeline?
    private let alertManager: AlertManager
    private let clock: Clock
    private let tuning: RideCameraTuning
    private let demoTuning: DemoTuning

    /// Confidence floor for accepting a near-miss event (Teammate B's measured
    /// number). Separate from any alert threshold.
    private let confidenceThreshold: Double

    // Injected seams (all fakeable).
    private let rideStateProvider: () -> RideState
    private let currentSpeedProvider: () -> Double
    private let cameraStateProvider: () -> CameraRecordingState
    private let storageStatusProvider: () -> StorageStatus
    private let isDetectionEnabled: () -> Bool
    private let isDemoMode: () -> Bool
    /// Whether detection auto-pinning is allowed at all (off until Teammate B's
    /// measured thresholds exist, O-CAM6). When false, events are still recorded
    /// but no clip is pinned.
    private let isAutoPinEnabled: () -> Bool
    private let currentRideId: () -> UUID?
    private let routeCoordinate: (Date) -> RouteCoordinate?
    /// Records a near-miss event locally (never uploaded here).
    private let recordNearMiss: (NearMissEvent) -> Void
    /// Pins a detection clip around the instant; returns the local clip id or nil.
    private let pinDetectionClip: (Date) -> UUID?
    private let makeEventId: () -> UUID

    // Per-ride state.
    private var lastAlertFiredAt: Date?
    private var lastAcceptedEventAt: Date?
    private var autoPinsThisRide = 0
    private var isRegistered = false

    init(
        detector: HazardDetector,
        pipeline: FramePipeline?,
        alertManager: AlertManager,
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning(),
        demoTuning: DemoTuning = DemoTuning(),
        confidenceThreshold: Double,
        rideStateProvider: @escaping () -> RideState,
        currentSpeedProvider: @escaping () -> Double,
        cameraStateProvider: @escaping () -> CameraRecordingState,
        storageStatusProvider: @escaping () -> StorageStatus = { .ok },
        isDetectionEnabled: @escaping () -> Bool,
        isDemoMode: @escaping () -> Bool = { false },
        isAutoPinEnabled: @escaping () -> Bool = { false },
        currentRideId: @escaping () -> UUID?,
        routeCoordinate: @escaping (Date) -> RouteCoordinate? = { _ in nil },
        recordNearMiss: @escaping (NearMissEvent) -> Void = { _ in },
        pinDetectionClip: @escaping (Date) -> UUID? = { _ in nil },
        makeEventId: @escaping () -> UUID = { UUID() }
    ) {
        self.detector = detector
        self.pipeline = pipeline
        self.alertManager = alertManager
        self.clock = clock
        self.tuning = tuning
        self.demoTuning = demoTuning
        self.confidenceThreshold = confidenceThreshold
        self.rideStateProvider = rideStateProvider
        self.currentSpeedProvider = currentSpeedProvider
        self.cameraStateProvider = cameraStateProvider
        self.storageStatusProvider = storageStatusProvider
        self.isDetectionEnabled = isDetectionEnabled
        self.isDemoMode = isDemoMode
        self.isAutoPinEnabled = isAutoPinEnabled
        self.currentRideId = currentRideId
        self.routeCoordinate = routeCoordinate
        self.recordNearMiss = recordNearMiss
        self.pinDetectionClip = pinDetectionClip
        self.makeEventId = makeEventId

        self.detector.onDetection = { [weak self] detection in
            // Delivered on the main actor by the detector contract.
            MainActor.assumeIsolated {
                self?.handle(detection)
            }
        }
    }

    // MARK: - Lifecycle / registration

    /// Re-evaluate whether the detector should be running, and register/remove it
    /// with the pipeline accordingly. Call after any camera-state or toggle
    /// change (or use the convenience setters below).
    func refresh() {
        let shouldRun = cameraStateProvider().isRecording && isDetectionEnabled()
        if shouldRun {
            register()
        } else {
            unregister()
        }
    }

    /// Reset per-ride counters (call on a fresh ride start).
    func beginRide() {
        lastAlertFiredAt = nil
        lastAcceptedEventAt = nil
        autoPinsThisRide = 0
        refresh()
    }

    /// Tear down at ride end / feature disable.
    func endRide() {
        unregister()
    }

    private func register() {
        guard !isRegistered else { return }
        isRegistered = true
        if let pipeline, let consumer = detector as? FrameConsumer {
            pipeline.register(consumer)
        }
        detector.start()
    }

    private func unregister() {
        guard isRegistered else { return }
        isRegistered = false
        detector.stop()
        if let pipeline, let consumer = detector as? FrameConsumer {
            pipeline.remove(consumerID: consumer.consumerID)
        }
    }

    // MARK: - Detection handling

    private func handle(_ detection: HazardDetection) {
        routeAlert(detection)
        routeNearMiss(detection)
    }

    /// Alert routing: demo mode bypasses the gate; normal mode consults
    /// `RearAlertGate`; a fired alert honors the rear-vehicle cooldown.
    private func routeAlert(_ detection: HazardDetection) {
        let allowed: Bool
        if isDemoMode() {
            allowed = true   // forced-alert demo bypasses the "only while moving" gate
        } else {
            allowed = RearAlertGate.shouldDeliver(
                rideState: rideStateProvider(),
                currentSpeed: currentSpeedProvider(),
                tuning: demoTuning
            )
        }
        guard allowed else { return }

        let now = clock.now()
        guard AlertCooldown.shouldFire(
            lastFiredAt: lastAlertFiredAt,
            now: now,
            cooldown: tuning.rearVehicleAlertCooldown
        ) else { return }

        lastAlertFiredAt = now
        alertManager.fire(.cautionRearVehicle)
    }

    /// Near-miss / clip routing through the pure `NearMissPolicy`.
    private func routeNearMiss(_ detection: HazardDetection) {
        let cameraRecording = cameraStateProvider().isRecording
        let context = NearMissPolicy.Context(
            now: clock.now(),
            confidenceThreshold: confidenceThreshold,
            lastAcceptedEventAt: lastAcceptedEventAt,
            autoPinsThisRide: autoPinsThisRide,
            storageStatus: storageStatusProvider(),
            cameraRecording: cameraRecording
        )
        let decision = NearMissPolicy.decide(
            detection: detection,
            context: context,
            tuning: tuning
        )
        guard decision.recordsEvent else { return }
        guard let rideId = currentRideId() else { return }

        lastAcceptedEventAt = clock.now()

        // Pin a detection clip only when the policy allows it AND auto-pinning is
        // enabled (off until Teammate B supplies measured thresholds, O-CAM6).
        var localClipId: UUID?
        if decision.pinsClip, isAutoPinEnabled() {
            localClipId = pinDetectionClip(detection.timestamp)
            if localClipId != nil {
                autoPinsThisRide += 1
            }
        }

        let coordinate = routeCoordinate(detection.timestamp)
        let demoFlag = isDemoMode()
        var event = NearMissPolicy.makeEvent(
            id: makeEventId(),
            rideId: rideId,
            detection: detection,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            isDemo: demoFlag
        )
        // Link the local clip id (never uploaded) when a pin succeeded.
        if let localClipId {
            event = NearMissEvent(
                id: event.id,
                rideId: event.rideId,
                occurredAt: event.occurredAt,
                latitude: event.latitude,
                longitude: event.longitude,
                kind: event.kind,
                confidence: event.confidence,
                positionHint: event.positionHint,
                source: event.source,
                isDemo: event.isDemo,
                localClipId: localClipId
            )
        }
        recordNearMiss(event)
    }
}
