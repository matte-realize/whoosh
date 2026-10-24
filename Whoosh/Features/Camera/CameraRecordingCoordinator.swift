import Foundation
import Observation

/// The main-actor, `@Observable` coordinator that turns the pure
/// `CameraStateMachine` into real recording alongside a ride (rear-camera spec
/// task 19; Requirements 1.2–1.4, 5.9, 12.1–12.4, 17.1, 17.2, 17.4; design
/// "Architecture and layering" diagram, "Camera recording state machine").
///
/// It is the single place that:
/// - starts/stops capture **with the ride** (via the read-only `RideCameraBridge`;
///   the ride engine is never modified, D-CAM14);
/// - wires the capture service to the `FramePipeline` (so a `FrameConsumer`
///   detector can plug in) **and** the `SegmentRecorder` (so footage is written);
/// - feeds finished segments to the `RingBufferManager` for eviction;
/// - maps capture events + polled thermal/storage/battery into
///   `CameraReducerEvent`s, reduces them with the pure state machine, and
///   executes the returned **effects-as-data** against the real services;
/// - routes every camera notice through the injected `AlertManager` (phone
///   audio/haptic now; the watch later) — camera trouble is never silent;
/// - saves clips on an explicit rider action through the `ClipPinner`.
///
/// ## Invariants (privacy steering, design)
/// - **A camera failure never changes ride state or GPS points.** This type only
///   reads the ride through the bridge and calls camera services; it never calls
///   a ride intent.
/// - **Footage never leaves the device.** It only talks to the on-device
///   capture/record/store/pin services; it imports no networking.
/// - **Honest copy.** Any user-facing note is an experimental cue and cannot
///   guarantee detection or delivery.
@Observable
@MainActor
final class CameraRecordingCoordinator {
    // MARK: Injected seams

    @ObservationIgnored private let capture: CameraCapturing
    @ObservationIgnored private let pipeline: FramePipeline?
    @ObservationIgnored private let makeRecorder: (UUID) -> SegmentRecording
    @ObservationIgnored private let segmentStore: SegmentStore
    @ObservationIgnored private let clipPinner: ClipPinner
    @ObservationIgnored private let alertManager: AlertManager
    @ObservationIgnored private let powerMonitor: PowerStateMonitoring
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let tuning: RideCameraTuning
    @ObservationIgnored private let bridge: RideCameraBridge
    /// Supplies the rider's current recording preferences (quality, camera,
    /// whether recording is enabled). Read fresh at each ride start.
    @ObservationIgnored private let settings: () -> RearCameraSettings
    /// Called when a camera state change should be reflected elsewhere (e.g. the
    /// ride-mode controller's amber trouble dot). Optional.
    @ObservationIgnored var onStateChange: ((CameraRecordingState) -> Void)?
    /// Called after a manual save so the UI can toast (ride mode / ride screen).
    @ObservationIgnored var onClipSaved: ((Bool) -> Void)?
    /// Supplied by the composition root to set concrete-only capture properties
    /// (camera position, pixel-buffer `videoSink`) before start — the
    /// `CameraCapturing` protocol stays framework-free. No-op for the fake.
    @ObservationIgnored var configureCapture: ((CameraDevicePosition) -> Void)?

    // MARK: Observable state (read-only to the UI)

    /// The current camera subsystem state (drives the ride-screen chip).
    private(set) var state: CameraRecordingState = .off

    /// The active recorder for this ride (one per ride; rebuilt on start).
    @ObservationIgnored private var recorder: SegmentRecording?
    /// The ring-buffer eviction manager for this ride.
    @ObservationIgnored private var ringManager: RingBufferManager?
    /// Start attempts in the current `preparing` cycle (reducer guard).
    @ObservationIgnored private var startAttempts = 0
    /// Whether the single writer-failure restart was already used this ride.
    @ObservationIgnored private var writerRestartTried = false
    /// The profile the selector resolved for this ride.
    @ObservationIgnored private var resolvedProfile: CaptureProfile?
    /// Polling timer for thermal/storage/battery.
    @ObservationIgnored private var pollTimer: Cancellable?

    init(
        capture: CameraCapturing,
        pipeline: FramePipeline?,
        makeRecorder: @escaping (UUID) -> SegmentRecording,
        segmentStore: SegmentStore,
        clipPinner: ClipPinner,
        alertManager: AlertManager,
        bridge: RideCameraBridge,
        settings: @escaping () -> RearCameraSettings,
        powerMonitor: PowerStateMonitoring = ProcessInfoPowerMonitor(),
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning()
    ) {
        self.capture = capture
        self.pipeline = pipeline
        self.makeRecorder = makeRecorder
        self.segmentStore = segmentStore
        self.clipPinner = clipPinner
        self.alertManager = alertManager
        self.bridge = bridge
        self.settings = settings
        self.powerMonitor = powerMonitor
        self.clock = clock
        self.tuning = tuning

        capture.onEvent = { [weak self] event in
            self?.handleCaptureEvent(event)
        }
    }

    // MARK: - Ride lifecycle

    /// Start recording with a ride, if the feature is enabled. A no-op (and the
    /// ride is entirely unchanged) when recording is off. Camera failures never
    /// affect the ride.
    func rideStarted() {
        guard settings().recordingEnabled else { return }
        startAttempts = 0
        writerRestartTried = false
        resolvedProfile = settings().quality.profile
        // The concrete capture service needs its camera position set before
        // start; the composition root supplies this (the protocol stays clean).
        configureCapture?(settings().cameraPosition)
        send(.rideStarted)
    }

    /// Stop recording at ride end / feature disable: finalize, finish pending
    /// pins, delete unpinned segments, tear down. Safe to call when already off.
    func rideEnded() {
        guard state != .off else { return }
        send(.rideEndedOrFeatureDisabled)
    }

    // MARK: - Manual save (explicit rider action)

    /// Save a clip from the ring buffer on an explicit rider action, returning a
    /// simple outcome the ride-remote bridge / UI can reply with. Never blocks
    /// the capture path.
    @discardableResult
    func saveClip() -> ClipSaveOutcome {
        guard let rideId = bridge.rideId, let rideStart = bridge.rideStart else {
            onClipSaved?(false)
            return .nothingToSave
        }
        // Kick off the pin; reflect the eventual result via the toast callback.
        Task { @MainActor in
            let result = await clipPinner.saveManually(rideId: rideId, rideStart: rideStart)
            switch result {
            case .saved, .pending, .merged:
                alertManager.fire(.clipSaved)
                onClipSaved?(true)
            case .debounced:
                break
            case let .notSaved(reason):
                alertManager.fire(.clipNotSaved(reason))
                onClipSaved?(false)
            }
        }
        // The synchronous reply is optimistic for the remote; the toast is the
        // ground truth once the async pin resolves.
        return .pending
    }

    // MARK: - Reduce → apply

    private func send(_ event: CameraReducerEvent) {
        let context = makeContext()
        let reduction = CameraStateMachine.reduce(state, event, context)
        state = reduction.state
        for effect in reduction.effects { apply(effect) }
        onStateChange?(state)
    }

    private func makeContext() -> CameraReducerContext {
        CameraReducerContext(
            permission: .authorized, // recording only starts after the settings flow granted it
            storageMeetsStartMinimum: storageMeetsStartMinimum(),
            resolvedProfile: resolvedProfile ?? settings().quality.profile,
            rideActive: bridge.isRideActive,
            startAttempts: startAttempts,
            writerRestartTried: writerRestartTried,
            tuning: tuning
        )
    }

    private func apply(_ effect: CameraEffect) {
        switch effect {
        case let .startSession(profile):
            startAttempts += 1
            beginRecording(profile: profile)
        case let .applyProfileStep(profile):
            capture.apply(CaptureProfileStep(profile: profile, reason: .thermal, appliesLive: profile.framesPerSecond != resolvedProfile?.framesPerSecond))
        case .finalizeSegment:
            recorder?.finish()
        case .openNewSegmentWithDiscontinuity:
            // On resume the capture service opens a fresh segment via begin.
            if let profile = resolvedProfile {
                recorder?.begin(profile: profile, orientation: mountOrientation())
            }
        case .discardSegment:
            writerRestartTried = true
        case .teardownSession:
            teardown()
        case .finishPendingPins:
            finishPendingPins()
        case .deleteUnpinnedSegments:
            deleteUnpinnedSegments()
        case let .scheduleRetry(delay):
            scheduleRetry(after: delay)
        case .schedulePolling:
            schedulePolling()
        case .publishStatus:
            break // status publishing is handled by RideStatusPublisher elsewhere
        case let .alert(alert):
            fireCameraAlert(alert)
        }
    }

    // MARK: - Effect helpers

    private func beginRecording(profile: CaptureProfile) {
        guard let rideId = bridge.rideId else { return }
        let recorder = makeRecorder(rideId)
        self.recorder = recorder
        self.ringManager = RingBufferManager(segmentStore: segmentStore, rideId: rideId, tuning: tuning)
        recorder.onSegmentFinished = { [weak self] segment in
            self?.ringManager?.segmentFinished(segment)
        }
        recorder.onFailure = { [weak self] _ in
            self?.send(.writerFailed)
        }
        capture.recorder = recorder
        capture.start(
            profile: profile,
            orientation: mountOrientation(),
            audioEnabled: false // O-CAM5: audio off by default
        )
    }

    private func teardown() {
        pollTimer?.cancel()
        pollTimer = nil
        capture.stop()
        recorder = nil
        ringManager = nil
    }

    private func finishPendingPins() {
        guard let rideId = bridge.rideId else { return }
        Task { @MainActor in
            await clipPinner.finalizePending(rideId: rideId)
        }
    }

    private func deleteUnpinnedSegments() {
        guard let rideId = bridge.rideId else { return }
        let unpinned = segmentStore.segments(rideId: rideId).filter { !$0.isPinned }
        segmentStore.delete(ids: unpinned.map { $0.id })
    }

    private func scheduleRetry(after delay: TimeInterval) {
        pollTimer?.cancel()
        _ = clock.schedule(after: delay) { [weak self] in
            guard let self else { return }
            // From preparing: a retry means try to run the session again.
            if case .preparing = self.state {
                self.send(.sessionRunning)
            }
        }
    }

    private func schedulePolling() {
        pollTimer?.cancel()
        pollTimer = clock.schedule(after: tuning.statusHeartbeat) { [weak self] in
            self?.poll()
            self?.schedulePolling()
        }
    }

    /// Poll thermal/storage/battery and feed the reducer any stop it implies.
    /// Minimal for the demo path: a critical thermal state or a storage stop
    /// finalizes the camera; GPS is untouched.
    private func poll() {
        guard state.isRecording else { return }
        if !storageMeetsStopFloor() {
            send(.storageStop)
            return
        }
        if powerMonitor.isThermallyThrottled {
            // A serious/critical thermal state steps down; keep it simple and
            // reduce once (the reducer clamps repeated step-downs).
            send(.thermalStepDown)
        }
    }

    private func fireCameraAlert(_ alert: CameraAlert) {
        switch alert {
        case .interrupted:
            alertManager.fire(.cameraInterrupted)
        case .resumed:
            alertManager.fire(.cameraResumed)
        case .reduced:
            alertManager.fire(.cameraStopped(.thermal))
        case let .stopped(reason):
            alertManager.fire(.cameraStopped(reason))
        case .notStartedPermission:
            alertManager.fire(.cameraStopped(.permission))
        case .notStartedStorage:
            alertManager.fire(.cameraStopped(.storage))
        }
    }

    // MARK: - Capture events

    private func handleCaptureEvent(_ event: CameraCaptureEvent) {
        switch event {
        case .running:
            send(.sessionRunning)
        case let .interrupted(reason):
            send(.interrupted(reason))
        case .interruptionEnded:
            send(.interruptionEnded)
        case .runtimeError:
            send(.startFailure)
        case .systemPressureChanged:
            break
        }
    }

    // MARK: - Storage / orientation helpers

    private func freeBytes() -> Int64 { segmentStore.freeSpace() }

    private func storageMeetsStartMinimum() -> Bool {
        freeBytes() >= tuning.freeSpaceStart
    }

    private func storageMeetsStopFloor() -> Bool {
        freeBytes() >= tuning.freeSpaceStop
    }

    /// The mount orientation. For the demo path the phone is upright on the
    /// mount; Mount & frame can refine this later via Core Motion.
    private func mountOrientation() -> CameraMountOrientation { .portrait }
}
