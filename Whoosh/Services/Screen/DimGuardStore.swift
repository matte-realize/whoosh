import Foundation

/// Persists the ride-mode **dim guard** so a run that dimmed the screen and then
/// crashed, was force-quit, or was killed in the background can restore the
/// rider's original brightness on the next launch (rear-camera spec Requirement
/// 10.2, design "Ride mode" / `BrightnessGuardState`, `ScreenModeStateMachine`
/// rows 2/8/12/14).
///
/// The stored value is a `BrightnessGuardState` — two 0...1 brightness fractions
/// (the rider's original and the dim target). It holds **no** location, camera,
/// or personal data, so persisting it in `UserDefaults` carries no privacy risk.
///
/// `@MainActor` because ride mode and the screen controller run on the main
/// actor (project default isolation); the `RideModeController` writes the guard
/// when it dims (row 2) and clears it on every restore path (rows 8, 12, 14).
@MainActor
protocol DimGuardStore: AnyObject {
    /// The persisted dim guard, or `nil` if ride mode is not currently dimming.
    var guardState: BrightnessGuardState? { get }

    /// Persist the dim guard (ride mode dimmed the screen).
    func store(_ state: BrightnessGuardState)

    /// Clear the persisted guard (the brightness has been restored).
    func clear()
}

/// `UserDefaults`-backed `DimGuardStore`. The guard is stored as a single JSON
/// blob under a dedicated key (injectable suite + key for tests). Reading back a
/// value written by a newer or corrupt build fails closed to `nil` (no guard)
/// rather than crashing — the worst case is the rider restores brightness
/// manually once.
@MainActor
final class UserDefaultsDimGuardStore: DimGuardStore {
    /// The `UserDefaults` key under which the dim guard is stored.
    static let defaultsKey = "whoosh.screen.dimGuard"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    var guardState: BrightnessGuardState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(BrightnessGuardState.self, from: data)
    }

    func store(_ state: BrightnessGuardState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory `DimGuardStore` for unit tests and previews. Lives under
/// `Services/Screen` (not the test target) so previews and the composition root
/// can inject it; tests reach it via `@testable import`.
@MainActor
final class InMemoryDimGuardStore: DimGuardStore {
    private(set) var guardState: BrightnessGuardState?

    init(guardState: BrightnessGuardState? = nil) {
        self.guardState = guardState
    }

    func store(_ state: BrightnessGuardState) {
        guardState = state
    }

    func clear() {
        guardState = nil
    }
}
