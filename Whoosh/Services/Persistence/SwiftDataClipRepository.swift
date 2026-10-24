import Foundation
import OSLog
import SwiftData

/// SwiftData-backed `ClipRepository` (rear-camera spec task 15; Requirement 8).
///
/// Maps the domain `ClipRecord` value type to/from the persisted
/// `ClipRecordEntity` entirely inside this type, so storage concerns never leak
/// upward. The record is encoded as a JSON blob on the entity, with `rideId`,
/// `createdAt`, and `expiresAt` denormalized for querying. `clips(rideId:)` and
/// `expired(now:)` skip (and log) any row whose blob fails to decode rather than
/// throwing, so a single corrupt row cannot break the whole list (the same
/// policy as `SwiftDataRideRepository`).
///
/// Clips are a **separate** repository from `RideRecord` (D-CAM8), so the
/// shipped ride model never migrates; the cascade on ride deletion runs through
/// `deleteAll(rideId:)` from a small cleanup hook. Footage is on-device only and
/// never uploaded, linked, or put in a message.
///
/// `@MainActor` because SwiftData's `ModelContext` is used on the main actor in
/// this project (default MainActor isolation).
@MainActor
final class SwiftDataClipRepository: ClipRepository {
    private let context: ModelContext
    /// A `ModelContext` does not keep its container alive; fetching after the
    /// container is freed traps inside SwiftData. Holding it here means callers
    /// can pass `container.mainContext` without retaining the container (the
    /// same lesson as `SwiftDataRideRepository` / `SwiftDataCrashAlertRepository`).
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "SwiftDataClipRepository"
    )

    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    // MARK: ClipRepository

    func save(_ clip: ClipRecord) throws {
        let encoded = try encoder.encode(clip)
        let id = clip.id
        let descriptor = FetchDescriptor<ClipRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.rideId = clip.rideId
            existing.createdAt = clip.createdAt
            existing.expiresAt = clip.expiresAt
            existing.encodedRecord = encoded
        } else {
            context.insert(
                ClipRecordEntity(
                    id: clip.id,
                    rideId: clip.rideId,
                    createdAt: clip.createdAt,
                    expiresAt: clip.expiresAt,
                    encodedRecord: encoded
                )
            )
        }
        try context.save()
    }

    func clips(rideId: UUID) throws -> [ClipRecord] {
        let descriptor = FetchDescriptor<ClipRecordEntity>(
            predicate: #Predicate { $0.rideId == rideId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap { clip(from: $0) }
    }

    func clip(id: UUID) throws -> ClipRecord? {
        let descriptor = FetchDescriptor<ClipRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        guard let entity = try context.fetch(descriptor).first else { return nil }
        return clip(from: entity)
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<ClipRecordEntity>(
            predicate: #Predicate { $0.id == id }
        )
        // Deleting a missing id is a safe no-op.
        guard let entity = try context.fetch(descriptor).first else { return }
        context.delete(entity)
        try context.save()
    }

    func deleteAll(rideId: UUID) throws {
        try context.delete(
            model: ClipRecordEntity.self,
            where: #Predicate { $0.rideId == rideId }
        )
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: ClipRecordEntity.self)
        try context.save()
    }

    func expired(now: Date) throws -> [ClipRecord] {
        let descriptor = FetchDescriptor<ClipRecordEntity>(
            predicate: #Predicate { $0.expiresAt <= now },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap { clip(from: $0) }
    }

    func totalBytes() throws -> Int64 {
        let descriptor = FetchDescriptor<ClipRecordEntity>()
        return try context.fetch(descriptor)
            .compactMap { clip(from: $0) }
            .reduce(0) { $0 + $1.bytes }
    }

    // MARK: Mapping

    /// Maps an entity to a domain `ClipRecord`, returning `nil` (after logging)
    /// if its blob cannot be decoded, so callers can skip it.
    private func clip(from entity: ClipRecordEntity) -> ClipRecord? {
        do {
            return try decoder.decode(ClipRecord.self, from: entity.encodedRecord)
        } catch {
            Self.logger.error(
                "Skipping clip \(entity.id, privacy: .public): blob failed to decode (\(String(describing: error), privacy: .public))"
            )
            return nil
        }
    }
}
