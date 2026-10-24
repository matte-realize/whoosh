import Foundation

/// `UserDefaults`-backed `RearCameraSettings` persistence (rear-camera spec
/// task 20). Stores one JSON blob under a stable key so adding a field later
/// does not need a migration; a missing or undecodable value falls back to the
/// defaults (recording off), so a corrupt entry can never force the camera on.
///
/// The `UserDefaults` suite is injectable so tests use an isolated store.
@MainActor
final class UserDefaultsRearCameraSettingsStore: RearCameraSettingsStore {
    /// Stable `UserDefaults` key for the persisted rear-camera settings.
    static let defaultsKey = "whoosh.settings.rearCamera"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RearCameraSettings {
        guard
            let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(RearCameraSettings.self, from: data)
        else {
            return .defaults
        }
        return decoded
    }

    func save(_ settings: RearCameraSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
