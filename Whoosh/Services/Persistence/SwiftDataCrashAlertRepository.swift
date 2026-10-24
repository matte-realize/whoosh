import Foundation
import OSLog
import SwiftData

/// SwiftData-backed `CrashAlertRepository` (spec Requirement 11.1, 11.3, 11.5,
/// 11.9).
///
/// Maps the domain `CrashAlertRecord` value type to/from the persisted
/// `CrashAlertRecordEntity` entirely inside this type, so storage concerns never
/// leak upward. The record is encoded as a JSON blob on the entity (the full
/// record, which carries only masked numbers); `all()` skips (and logs) any row
/// whose blob fails to decode rather than throwing, so a single corrupt row
/// cannot break the whole log (same policy as `SwiftDataRideRepository`).
///
/// `@MainActor` because SwiftData's `ModelContext` is used on the main actor in
/// this project (default MainActor isolation).
@MainActor
final class SwiftDataCrashAlertRepository: CrashAlertRepository {
    private let context: ModelContext
    /// A `ModelContext` does not keep its container alive; fetching after the
    /// container is freed traps inside SwiftData. Holding it here means callers
    /// can pass `container.mainContext` without retaining the container (the
    /// same lesson as `SwiftDataRideRepository`).
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "SwiftDataCrashAlertRepository"
    )

    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    func save(_ record: CrashAlertRecord) throws {
        let encoded = try encoder.encode(record)
        let id = record.id
        let detectedAt = record.event.detectedAt
        let stateRaw = record.event.state.rawValue
        // Upsert: update an existing row with the same id, else insert.
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.detectedAt = detectedAt
            existing.stateRaw = stateRaw
            existing.encodedRecord = encoded
        } else {
            context.insert(
                CrashAlertRecordEntity(
                    id: id,
                    detectedAt: detectedAt,
                    stateRaw: stateRaw,
                    encodedRecord: encoded
                )
            )
        }
        try context.save()
    }

    func all() throws -> [CrashAlertRecord] {
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )
        let entities = try context.fetch(descriptor)
        // Skip (and log) undecodable rows instead of throwing.
        return entities.compactMap { record(from: $0) }
    }

    func record(id: UUID) throws -> CrashAlertRecord? {
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else {
            return nil
        }
        return record(from: entity)
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        // Deleting a missing id is a safe no-op (Requirement 11.5).
        guard let entity = try context.fetch(descriptor).first else {
            return
        }
        context.delete(entity)
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: CrashAlertRecordEntity.self)
        try context.save()
    }

    func purge(olderThan date: Date) throws {
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            predicate: #Predicate { $0.detectedAt < date }
        )
        let stale = try context.fetch(descriptor)
        for entity in stale {
            context.delete(entity)
        }
        try context.save()
    }

    func activeEvent() throws -> CrashAlertRecord? {
        // Filter by the denormalized state, newest first; decode and re-check
        // the active flag defensively (and skip corrupt rows).
        let activeRaws = Set(
            CrashEventState.allCases.filter(\.isActive).map(\.rawValue)
        )
        let descriptor = FetchDescriptor<CrashAlertRecordEntity>(
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )
        let entities = try context.fetch(descriptor)
        for entity in entities where activeRaws.contains(entity.stateRaw) {
            if let record = record(from: entity), record.event.state.isActive {
                return record
            }
        }
        return nil
    }

    // MARK: Mapping

    /// Maps an entity to a domain `CrashAlertRecord`, returning `nil` (after
    /// logging) if its blob cannot be decoded, so callers can skip it.
    private func record(from entity: CrashAlertRecordEntity) -> CrashAlertRecord? {
        do {
            return try decoder.decode(CrashAlertRecord.self, from: entity.encodedRecord)
        } catch {
            Self.logger.error(
                "Skipping crash record \(entity.id, privacy: .public): blob failed to decode (\(String(describing: error), privacy: .public))"
            )
            return nil
        }
    }
}
