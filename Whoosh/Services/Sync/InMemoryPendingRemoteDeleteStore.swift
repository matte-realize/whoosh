import Foundation

/// In-memory `PendingRemoteDeleteStore` for unit tests and previews.
///
/// Keeps tombstones in a `Set` so `add` deduplicates and `remove` of an absent
/// id is a safe no-op. No persistence across launches — that is the
/// `UserDefaults` implementation's job. Lives under `Services/Sync` (not the
/// test target) so the composition root and previews can inject it; tests reach
/// it via `@testable import`.
final class InMemoryPendingRemoteDeleteStore: PendingRemoteDeleteStore {
    private var ids: Set<UUID>

    init(ids: [UUID] = []) {
        self.ids = Set(ids)
    }

    func allPending() -> [UUID] {
        Array(ids)
    }

    func add(_ id: UUID) {
        ids.insert(id)
    }

    func remove(_ id: UUID) {
        ids.remove(id)
    }
}
