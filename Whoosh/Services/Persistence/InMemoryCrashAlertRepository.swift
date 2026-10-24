import Foundation

/// In-memory `CrashAlertRepository` for unit tests and SwiftUI previews.
///
/// Keeps records in a dictionary keyed by id, so `save` upserts and `delete` of
/// a missing id is a harmless no-op. `all()` sorts most-recent-first by the
/// event's `detectedAt`. No persistence across launches — that is the SwiftData
/// implementation's job.
///
/// Lives under `Services/Persistence/` (not the test target) so the composition
/// root and previews can inject it; tests reach it via `@testable import`.
@MainActor
final class InMemoryCrashAlertRepository: CrashAlertRepository {
    private var recordsByID: [UUID: CrashAlertRecord] = [:]

    init(records: [CrashAlertRecord] = []) {
        for record in records {
            recordsByID[record.id] = record
        }
    }

    func save(_ record: CrashAlertRecord) throws {
        recordsByID[record.id] = record
    }

    func all() throws -> [CrashAlertRecord] {
        recordsByID.values.sorted { $0.event.detectedAt > $1.event.detectedAt }
    }

    func record(id: UUID) throws -> CrashAlertRecord? {
        recordsByID[id]
    }

    func delete(id: UUID) throws {
        recordsByID.removeValue(forKey: id)
    }

    func deleteAll() throws {
        recordsByID.removeAll()
    }

    func purge(olderThan date: Date) throws {
        recordsByID = recordsByID.filter { $0.value.event.detectedAt >= date }
    }

    func activeEvent() throws -> CrashAlertRecord? {
        // At most one event is active at a time (Requirement 6.9); return the
        // most recent active one defensively if more than one ever exists.
        recordsByID.values
            .filter { $0.event.state.isActive }
            .sorted { $0.event.detectedAt > $1.event.detectedAt }
            .first
    }
}
