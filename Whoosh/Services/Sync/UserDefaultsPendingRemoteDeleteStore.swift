import Foundation

/// `UserDefaults`-backed `PendingRemoteDeleteStore` (Requirement 12.6).
///
/// Persists the tombstone set as an array of UUID strings under a single key so
/// offline deletes survive an app relaunch and still propagate to the backend
/// on the next sync. Deduplicates on write (a set semantics), so adding the
/// same id twice stores it once.
///
/// Holds only ride ids — never route points or any personal data — so writing
/// it to `UserDefaults` carries no privacy risk.
final class UserDefaultsPendingRemoteDeleteStore: PendingRemoteDeleteStore {
    /// The `UserDefaults` key under which the tombstone ids are stored.
    static let defaultsKey = "whoosh.sync.pendingRemoteDeletes"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    func allPending() -> [UUID] {
        let raw = defaults.stringArray(forKey: key) ?? []
        return raw.compactMap(UUID.init(uuidString:))
    }

    func add(_ id: UUID) {
        var ids = Set(allPending())
        ids.insert(id)
        persist(ids)
    }

    func remove(_ id: UUID) {
        var ids = Set(allPending())
        ids.remove(id)
        persist(ids)
    }

    private func persist(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}
