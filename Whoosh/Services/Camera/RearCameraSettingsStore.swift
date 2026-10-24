import Foundation

/// The persisted rear-camera settings (rear-camera spec Requirement 18.1, task
/// 20). One value type holds every rider-adjustable recording preference so the
/// Settings view model and the composition root read/write them in one place.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`. Defaults
/// match the design (`RideCameraTuning`) and O-CAM resolutions: recording **off
/// by default**, **back** wide camera, **Standard** quality, ride mode **on**,
/// a 10-minute buffer.
struct RearCameraSettings: Equatable, Codable, Sendable {
    /// Whether rear camera recording is enabled. ON by default in the hackathon
    /// build (owner decision, October 24, 2026); the camera permission prompt
    /// appears the first time a ride needs the camera.
    var recordingEnabled: Bool
    /// Which camera to record with (back by default; front option).
    var cameraPosition: CameraDevicePosition
    /// The recording quality (Standard / Efficient).
    var quality: CaptureQuality
    /// Whether ride mode (true-black, touch-locked) is used while recording
    /// (on by default when the camera records; Requirement 10.8).
    var rideModeEnabled: Bool
    /// The rolling-buffer length in seconds ("Buffer length"); clamped to
    /// `RideCameraTuning.ringMaxDurationRange`.
    var bufferLengthSeconds: TimeInterval

    init(
        recordingEnabled: Bool = true,
        cameraPosition: CameraDevicePosition = .back,
        quality: CaptureQuality = .standard,
        rideModeEnabled: Bool = true,
        bufferLengthSeconds: TimeInterval = 10 * 60
    ) {
        self.recordingEnabled = recordingEnabled
        self.cameraPosition = cameraPosition
        self.quality = quality
        self.rideModeEnabled = rideModeEnabled
        self.bufferLengthSeconds = bufferLengthSeconds
    }

    /// The default settings (recording off, back camera, Standard, ride mode on).
    static let defaults = RearCameraSettings()
}

/// Abstracts persistence of `RearCameraSettings` so the Settings view model and
/// composition root are testable without touching `UserDefaults` directly
/// (rear-camera spec task 20). `UserDefaultsRearCameraSettingsStore` is the
/// live type; `InMemoryRearCameraSettingsStore` backs tests and previews.
///
/// Reads and writes run on the main actor (the Settings view model's isolation).
@MainActor
protocol RearCameraSettingsStore: AnyObject {
    /// Load the current settings (defaults when nothing is stored).
    func load() -> RearCameraSettings
    /// Persist the settings.
    func save(_ settings: RearCameraSettings)
}
