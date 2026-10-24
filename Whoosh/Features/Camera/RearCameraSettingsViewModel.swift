import Foundation
import Observation

/// Drives the "Rear camera" Settings section and the first-enable permission
/// flow (rear-camera spec Requirement 2.1–2.7, 18.1; task 20). `@Observable` and
/// **UI-framework-free** (no SwiftUI import) per the layering table: the view
/// observes it and sends intents.
///
/// ## Permission flow (Requirement 2.1–2.4)
/// - The camera is **never** requested at launch or on Home; the system prompt
///   is triggered only when the rider first enables "Record rear camera", and
///   only **after** the in-app explanation (what is recorded, that it stays on
///   the device, that other people may appear, that local laws vary).
/// - Enabling from `notDetermined` ⇒ show the explanation sheet; on
///   acknowledgement, `request()`; if `authorized`, recording turns on; if
///   `denied`/`restricted`, it stays off with an "Open Settings" path.
/// - Enabling while already `authorized` turns recording on without a prompt.
/// - Enabling while `denied`/`restricted` does not re-prompt (the system never
///   re-prompts): it surfaces the denied state and the Settings path.
/// - A permission change (including returning from Settings) arrives through
///   `CameraPermission.onChange` and updates the UI without a restart;
///   revocation while recording turns the stored flag off (Requirement 2.4).
///
/// Nothing here imports AVFoundation — the `CameraPermission` seam owns that.
@Observable
@MainActor
final class RearCameraSettingsViewModel {
    @ObservationIgnored private let permission: CameraPermission
    @ObservationIgnored private let store: RearCameraSettingsStore
    @ObservationIgnored private let clipRepository: ClipRepository
    @ObservationIgnored private let tuning: RideCameraTuning

    /// The current rear-camera settings (persisted on every change).
    private(set) var settings: RearCameraSettings
    /// The live camera authorization state, mirrored in the UI.
    private(set) var permissionStatus: CameraPermissionStatus

    /// `true` while the first-enable explanation sheet should be shown. The view
    /// binds its sheet to this; acknowledging calls `acknowledgeExplanation()`,
    /// dismissing calls `dismissExplanation()`.
    var isShowingExplanation = false

    /// Total bytes used by saved clips, for the Settings "storage used" row.
    /// Refreshed by `refreshStorageUsed()`; `nil` until first read.
    private(set) var clipBytesUsed: Int64?

    /// Invoked when the rider taps "Open Settings" from a denied/restricted
    /// state. The composition root wires this to open the system Settings app
    /// (so this view model stays UIKit-free).
    @ObservationIgnored var onOpenSystemSettings: (() -> Void)?

    init(
        permission: CameraPermission,
        store: RearCameraSettingsStore,
        clipRepository: ClipRepository,
        tuning: RideCameraTuning = RideCameraTuning()
    ) {
        self.permission = permission
        self.store = store
        self.clipRepository = clipRepository
        self.tuning = tuning
        self.settings = store.load()
        self.permissionStatus = permission.status

        // Reflect system authorization changes (grant, denial, returning from
        // Settings) without a restart; a revocation turns recording off.
        permission.onChange = { [weak self] status in
            self?.handlePermissionChange(status)
        }
    }

    // MARK: - Derived UI state

    /// Whether recording is currently on.
    var recordingEnabled: Bool { settings.recordingEnabled }

    /// Whether the denied/restricted explanation + "Open Settings" row should
    /// show (the rider tried to record but access is blocked).
    var showsDeniedState: Bool {
        permissionStatus == .denied || permissionStatus == .restricted
    }

    /// The buffer-length range the control is bound to (minutes come from the
    /// tuning range).
    var bufferLengthRange: ClosedRange<TimeInterval> { tuning.ringMaxDurationRange }

    // MARK: - Recording toggle (the permission flow)

    /// The rider flipped the "Record rear camera" switch.
    func setRecordingEnabled(_ enabled: Bool) {
        if enabled {
            enableRecording()
        } else {
            // Turning off never prompts; just persist.
            apply { $0.recordingEnabled = false }
        }
    }

    /// Enable recording, driving the permission flow by current status.
    private func enableRecording() {
        switch permissionStatus {
        case .authorized:
            // Already granted: turn on without a prompt.
            apply { $0.recordingEnabled = true }
        case .notDetermined:
            // Explain first; the prompt is only shown on acknowledgement.
            isShowingExplanation = true
        case .denied, .restricted:
            // The system won't re-prompt; surface the denied state + Settings
            // path. Recording stays off.
            apply { $0.recordingEnabled = false }
        }
    }

    /// The rider acknowledged the first-enable explanation; now (and only now)
    /// request camera access and turn recording on if granted.
    func acknowledgeExplanation() async {
        isShowingExplanation = false
        let status = await permission.request()
        permissionStatus = status
        if status == .authorized {
            apply { $0.recordingEnabled = true }
        } else {
            // Denied/restricted at the prompt: stay off; the denied state shows.
            apply { $0.recordingEnabled = false }
        }
    }

    /// The rider dismissed the explanation without proceeding; nothing is
    /// requested and recording stays off.
    func dismissExplanation() {
        isShowingExplanation = false
        apply { $0.recordingEnabled = false }
    }

    /// The rider tapped "Open Settings" from a denied/restricted state.
    func openSystemSettings() {
        onOpenSystemSettings?()
    }

    // MARK: - Other settings

    /// Change the recording camera (back/front).
    func setCameraPosition(_ position: CameraDevicePosition) {
        apply { $0.cameraPosition = position }
    }

    /// Change the recording quality (Standard/Efficient).
    func setQuality(_ quality: CaptureQuality) {
        apply { $0.quality = quality }
    }

    /// Toggle ride mode on/off.
    func setRideModeEnabled(_ enabled: Bool) {
        apply { $0.rideModeEnabled = enabled }
    }

    /// Change the rolling-buffer length (clamped to the allowed range).
    func setBufferLengthSeconds(_ seconds: TimeInterval) {
        let clamped = tuning.clampRingMaxDuration(seconds)
        apply { $0.bufferLengthSeconds = clamped }
    }

    // MARK: - Storage used

    /// Recompute the clip storage-used figure for the Settings row.
    func refreshStorageUsed() {
        clipBytesUsed = (try? clipRepository.totalBytes()) ?? 0
    }

    // MARK: - Private

    /// Apply a mutation and persist it.
    private func apply(_ mutate: (inout RearCameraSettings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }
        settings = next
        store.save(next)
    }

    /// React to a system authorization change.
    private func handlePermissionChange(_ status: CameraPermissionStatus) {
        permissionStatus = status
        // If access was revoked while recording was on, turn the stored flag off
        // so the UI is honest (recording cannot run without authorization).
        if status != .authorized, settings.recordingEnabled {
            apply { $0.recordingEnabled = false }
        }
    }
}
