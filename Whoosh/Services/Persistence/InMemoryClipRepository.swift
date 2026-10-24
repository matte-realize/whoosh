import Foundation

/// In-memory `ClipRepository` used by unit tests and SwiftUI previews.
///
/// Keeps clips in a dictionary keyed by `id`, so `save` upserts and `delete` of
/// a missing id is a harmless no-op. `clips(rideId:)` sorts most-recent-first by
/// `createdAt`; `expired(now:)` returns clips at or past their retention expiry.
/// No persistence across process launches — that is the SwiftData implementation's
/// job (task 15).
///
/// Lives under `Services/Persistence/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
final class InMemoryClipRepository: ClipRepository {
    private var clipsByID: [UUID: ClipRecord] = [:]

    init(clips: [ClipRecord] = []) {
        for clip in clips { clipsByID[clip.id] = clip }
    }

    func save(_ clip: ClipRecord) throws {
        clipsByID[clip.id] = clip
    }

    func clips(rideId: UUID) throws -> [ClipRecord] {
        clipsByID.values
            .filter { $0.rideId == rideId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func clip(id: UUID) throws -> ClipRecord? {
        clipsByID[id]
    }

    func delete(id: UUID) throws {
        clipsByID.removeValue(forKey: id)
    }

    func deleteAll(rideId: UUID) throws {
        for (id, clip) in clipsByID where clip.rideId == rideId {
            clipsByID[id] = nil
        }
    }

    func deleteAll() throws {
        clipsByID.removeAll()
    }

    func expired(now: Date) throws -> [ClipRecord] {
        clipsByID.values
            .filter { $0.isExpired(at: now) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func totalBytes() throws -> Int64 {
        clipsByID.values.reduce(0) { $0 + $1.bytes }
    }
}
