import Foundation

/// Abstraction over device-local crash-alert feature settings (spec design
/// "Entities": `CrashAlertSettings`). Stored in `UserDefaults` — the feature
/// toggle, rider label, optional countdown override, and developer-tools flag.
/// **No contact data** lives here (that is Keychain only).
///
/// `UserDefaultsCrashAlertSettingsStore` is the shipping implementation;
/// `InMemoryCrashAlertSettingsStore` backs unit tests and previews. Runs on the
/// main actor, consistent with the other stores.
@MainActor
protocol CrashAlertSettingsStore {
    /// The current settings, or the default (feature off) if none saved yet.
    func current() -> CrashAlertSettings

    /// Persist the given settings, replacing the previous value.
    func save(_ settings: CrashAlertSettings)
}

/// `UserDefaults`-backed `CrashAlertSettingsStore`. Stores the settings as a
/// single JSON blob under a dedicated key (injectable suite + key for tests).
/// Off by default (Requirement 1.4): an absent value decodes to the default
/// `CrashAlertSettings()` with `enabled == false`.
@MainActor
final class UserDefaultsCrashAlertSettingsStore: CrashAlertSettingsStore {
    /// The `UserDefaults` key under which the settings are stored.
    static let defaultsKey = "whoosh.crash.settings"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    func current() -> CrashAlertSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? decoder.decode(CrashAlertSettings.self, from: data)
        else {
            // Absent or undecodable ⇒ feature off (fail closed, Requirement 1.4).
            return CrashAlertSettings()
        }
        return settings
    }

    func save(_ settings: CrashAlertSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory `CrashAlertSettingsStore` for unit tests and previews.
@MainActor
final class InMemoryCrashAlertSettingsStore: CrashAlertSettingsStore {
    private var settings: CrashAlertSettings

    init(settings: CrashAlertSettings = CrashAlertSettings()) {
        self.settings = settings
    }

    func current() -> CrashAlertSettings { settings }

    func save(_ settings: CrashAlertSettings) {
        self.settings = settings
    }
}
