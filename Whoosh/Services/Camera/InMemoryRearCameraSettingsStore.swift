import Foundation

/// In-memory `RearCameraSettingsStore` for tests and SwiftUI previews
/// (rear-camera spec task 20). Lives under `Services/Camera/` (not the test
/// target) so previews and the composition root can inject it.
@MainActor
final class InMemoryRearCameraSettingsStore: RearCameraSettingsStore {
    private var settings: RearCameraSettings
    /// Number of `save` calls (for test assertions).
    private(set) var saveCount = 0

    init(settings: RearCameraSettings = .defaults) {
        self.settings = settings
    }

    func load() -> RearCameraSettings { settings }

    func save(_ settings: RearCameraSettings) {
        self.settings = settings
        saveCount += 1
    }
}
