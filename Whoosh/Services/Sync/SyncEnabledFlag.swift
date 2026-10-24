import Foundation

/// A tiny thread-safe boolean shared between the (MainActor) Settings layer and
/// the off-main-actor `SupabaseRideSyncService` (task 28e).
///
/// The service's `isEnabled` must be `@Sendable` (it runs on an actor), so it
/// can't capture the MainActor `SettingsViewModel` directly. This box lets the
/// composition root publish the current "sync enabled" value from the main
/// actor and lets the service read it from any isolation, with no data race.
nonisolated final class SyncEnabledFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool = false) {
        self.value = value
    }

    var isOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
