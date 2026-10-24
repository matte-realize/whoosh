import Foundation

/// Tracks whether the app has launched before, in **app-container storage**
/// (which is deleted when the app is deleted) rather than the Keychain (which
/// is not). On first launch after a fresh install the marker is absent, so the
/// contact store knows to purge any orphaned Keychain items left behind by a
/// previous install (spec Requirement 2.8, design iOS investigation #9).
///
/// A tiny seam so the "purge on fresh install" logic is unit-testable without
/// touching real `UserDefaults`: `InMemoryFreshInstallMarkerStore` backs tests,
/// `UserDefaultsFreshInstallMarkerStore` is the shipping implementation.
///
/// Runs on the main actor, consistent with the contact store it supports.
@MainActor
protocol FreshInstallMarkerStore {
    /// `true` once `markInstalled()` has run in a previous launch of this
    /// install; `false` on the first launch after a fresh install.
    func hasLaunchedBefore() -> Bool

    /// Record that the app has now launched, so later launches are not treated
    /// as fresh installs.
    func markInstalled()
}

/// `UserDefaults`-backed `FreshInstallMarkerStore`. The marker is a single bool
/// under a dedicated key; it lives in the app container and is removed with the
/// app, which is exactly the signal we need (Requirement 2.8). It stores no
/// contact data.
@MainActor
final class UserDefaultsFreshInstallMarkerStore: FreshInstallMarkerStore {
    /// The `UserDefaults` key under which the marker is stored.
    static let defaultsKey = "whoosh.crash.freshInstallMarker"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    func hasLaunchedBefore() -> Bool {
        defaults.bool(forKey: key)
    }

    func markInstalled() {
        defaults.set(true, forKey: key)
    }
}

/// In-memory `FreshInstallMarkerStore` for unit tests and previews. Starts as a
/// fresh install (`hasLaunchedBefore()` is `false`) unless seeded otherwise.
@MainActor
final class InMemoryFreshInstallMarkerStore: FreshInstallMarkerStore {
    private var launched: Bool

    init(hasLaunchedBefore: Bool = false) {
        self.launched = hasLaunchedBefore
    }

    func hasLaunchedBefore() -> Bool { launched }

    func markInstalled() { launched = true }
}
