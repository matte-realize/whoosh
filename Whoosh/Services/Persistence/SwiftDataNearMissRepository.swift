import Foundation
import OSLog
import SwiftData

/// SwiftData-backed `NearMissRepository` (rear-camera spec task 28; Requirement
/// 15).
///
/// Maps the domain `NearMissEvent` value type to/from the persisted
/// `NearMissEventEntity` entirely inside this type, so storage concerns never
/// leak upward. The event is encoded as a JSON blob on the entity, with
/// `rideId`, `occurredAt`, and `isDemo` denormalized for querying.
/// `events(rideId:)` skips (and logs) any row whose blob fails to decode rather
/// than throwing, so a single corrupt row cannot break the list (the same policy
/// as `SwiftDataRideRepository` / `SwiftDataClipRepository`).
///
/// Events are a **separate** repository from `RideRecord` (D-CAM8), so the
/// shipped ride model never migrates; the cascade on ride deletion runs through
/// `deleteAll(rideId:)`. The local clip id is on-device only and never uploaded.
///
/// `@MainActor` because SwiftData's `ModelContext` is used on the main actor in
/// this project (default MainActor isolation).
@MainActor
final class SwiftDataNearMissRepository: NearMissRepository {
    private let context: ModelContext
    /// A `ModelContext` does not keep its container alive; fetching after the
    /// container is freed traps inside SwiftData. Holding it here means callers
    /// can pass `container.mainContext` without retaining the container (the
    /// same lesson as the other SwiftData repositories).
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "SwiftDataNearMissRepository"
    )

    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    // MARK: NearMissRepository

    func save(_ event: NearMissEvent) throws {
        let encoded = try encoder.encode(event)
        let id = event.id
        let descriptor = FetchDescriptor<NearMissEventEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.rideId = event.rideId
            existing.occurredAt = event.occurredAt
            existing.isDemo = event.isDemo
            existing.encodedEvent = encoded
        } else {
            context.insert(
                NearMissEventEntity(
                    id: event.id,
                    rideId: event.rideId,
                    occurredAt: event.occurredAt,
                    isDemo: event.isDemo,
                    encodedEvent: encoded
                )
            )
        }
        try context.save()
    }

    func events(rideId: UUID) throws -> [NearMissEvent] {
        let descriptor = FetchDescriptor<NearMissEventEntity>(
            predicate: #Predicate { $0.rideId == rideId },
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        )
        return try context.fetch(descriptor).compactMap { event(from: $0) }
    }

    func deleteAll(rideId: UUID) throws {
        try context.delete(
            model: NearMissEventEntity.self,
            where: #Predicate { $0.rideId == rideId }
        )
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: NearMissEventEntity.self)
        try context.save()
    }

    // MARK: Mapping

    /// Maps an entity to a domain `NearMissEvent`, returning `nil` (after
    /// logging) if its blob cannot be decoded, so callers can skip it.
    private func event(from entity: NearMissEventEntity) -> NearMissEvent? {
        do {
            return try decoder.decode(NearMissEvent.self, from: entity.encodedEvent)
        } catch {
            Self.logger.error(
                "Skipping near-miss \(entity.id, privacy: .public): blob failed to decode (\(String(describing: error), privacy: .public))"
            )
            return nil
        }
    }
}
