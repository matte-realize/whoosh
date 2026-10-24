import Foundation
import Observation

/// Drives the Mount & frame screen (rear-camera spec task 22, Requirement 9,
/// 1.2, 18.2). `@Observable` and **UI-framework-free** (no SwiftUI import) per
/// the layering table: the view observes it and sends intents.
///
/// Shown after the rider taps Start Ride while rear detection/recording is on.
/// It owns the live preview host (from the capture service), a Core Motion level
/// reading via `MountLevelSensing`, the camera choice (back/front), and the
/// readiness checklist from the pure `ReadinessEvaluator`. Two outcomes:
/// - **Start ride mode** — begin the ride and enter ride mode with the camera;
/// - **Skip camera** — begin a normal ride without the camera.
///
/// It imports no AVFoundation or Core Motion directly — the `CameraPreviewHost`
/// and `MountLevelSensing` seams own those. Leaving the screen tears the preview
/// session down (the owner calls `stopPreview()`).
@Observable
@MainActor
final class MountAndFrameViewModel {
    // MARK: Injected seams

    @ObservationIgnored private let previewHost: CameraPreviewHost
    @ObservationIgnored private let levelSensor: MountLevelSensing
    @ObservationIgnored private let settingsStore: RearCameraSettingsStore
    @ObservationIgnored private let clock: Clock

    /// Begin a ride **with** the camera (the owner starts the ride session and
    /// enters ride mode). The chosen camera settings are already persisted.
    @ObservationIgnored var onStartWithCamera: (() -> Void)?
    /// Begin a **normal** ride without the camera (the owner starts the ride as
    /// it did before this feature).
    @ObservationIgnored var onSkipCamera: (() -> Void)?

    // MARK: Observable state

    /// The persisted rear-camera settings (camera choice, quality).
    private(set) var settings: RearCameraSettings
    /// The latest level reading, or `nil` until the first sample arrives.
    private(set) var level: LevelCalculator.Reading?

    @ObservationIgnored private let capture: CameraCapturing?
    @ObservationIgnored private let permission: CameraPermission?
    /// Whether this screen started the capture session for its preview.
    @ObservationIgnored private var startedPreview = false
    /// Set once the ride takes over the running session (do not stop it).
    @ObservationIgnored private var handedOff = false
    /// Camera authorization as seen by this screen (drives the "allow camera" note).
    private(set) var permissionStatus: CameraPermissionStatus = .notDetermined

    init(
        previewHost: CameraPreviewHost,
        levelSensor: MountLevelSensing,
        settingsStore: RearCameraSettingsStore,
        clock: Clock,
        capture: CameraCapturing? = nil,
        permission: CameraPermission? = nil
    ) {
        self.capture = capture
        self.permission = permission
        self.previewHost = previewHost
        self.levelSensor = levelSensor
        self.settingsStore = settingsStore
        self.clock = clock
        self.settings = settingsStore.load()
    }

    // MARK: - Preview host (for the representable)

    /// The host the `CameraPreviewView` wraps. The view asks for it once.
    var host: CameraPreviewHost { previewHost }

    // MARK: - Level indicator

    /// Start the level sensor and reflect readings into `level` via the pure
    /// `LevelCalculator` (no Core Motion in this view model).
    func startLevel() {
        levelSensor.onGravity = { [weak self] gravity in
            self?.level = LevelCalculator.reading(
                gx: gravity.x,
                gy: gravity.y,
                gz: gravity.z,
                orientation: .portrait
            )
        }
        levelSensor.start()
    }

    /// Stop the level sensor (leaving the screen).
    func stopLevel() {
        levelSensor.stop()
        levelSensor.onGravity = nil
    }

    /// A short, honest label for the current level state.
    var levelLabel: String {
        switch level?.classification {
        case .level: return "Level"
        case .slightlyOff: return "Tilt to level"
        case .none: return "Checking…"
        }
    }

    /// Whether the mount reads level (for the green/amber indicator).
    var isLevel: Bool { level?.classification == .level }

    // MARK: - Camera choice

    /// Change the recording camera (back/front) and persist it.
    func setCameraPosition(_ position: CameraDevicePosition) {
        guard position != settings.cameraPosition else { return }
        settings.cameraPosition = position
        settingsStore.save(settings)
    }

    // MARK: - Live preview

    /// Ask for camera access if needed (rear camera is on by default, so the
    /// Settings toggle may never have asked), then start the capture session so
    /// the preview is live while the rider aims. The ride reuses the session.
    func startPreview() async {
        guard let permission, let capture else { return }
        var status = permission.status
        if status == .notDetermined { status = await permission.request() }
        permissionStatus = status
        guard status == .authorized, !startedPreview else { return }
        capture.start(profile: .standard, orientation: .portrait, audioEnabled: false)
        startedPreview = true
    }

    /// Stop the preview session unless the ride has taken it over.
    func stopPreviewIfNeeded() {
        guard startedPreview, !handedOff else { return }
        capture?.stop()
        startedPreview = false
    }

    // MARK: - Actions

    /// Start the ride with the camera.
    func startWithCamera() {
        stopLevel()
        handedOff = true
        onStartWithCamera?()
    }

    /// Skip the camera and start a normal ride.
    func skipCamera() {
        stopLevel()
        stopPreviewIfNeeded()
        onSkipCamera?()
    }
}
