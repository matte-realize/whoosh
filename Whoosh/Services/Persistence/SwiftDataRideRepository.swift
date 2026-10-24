import Foundation
import OSLog
import SwiftData

/// SwiftData-backed `RideRepository` (Requirements 7.1–7.4, 7.6–7.8).
///
/// Maps the domain `Ride` value type to/from the persisted `RideRecord` entirely
/// inside this type, so storage concerns never leak upward. The route is encoded
/// as a JSON blob on the record; `allRides()` skips (and logs) any record whose
/// points fail to decode rather than throwing, so a single corrupt row cannot
/// break the whole history list (Requirement 7.7).
///
/// `@MainActor` because SwiftData's `ModelContext` is used on the main actor in
/// this project (default MainActor isolation), which keeps it directly usable
/// from `@MainActor` view models.
@MainActor
final class SwiftDataRideRepository: RideRepository {
    private let context: ModelContext
    /// A `ModelContext` does not keep its container alive; fetching after the
    /// container is freed traps inside SwiftData. Holding it here means callers
    /// can pass `container.mainContext` without retaining the container.
    private let container: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "SwiftDataRideRepository"
    )

    init(context: ModelContext) {
        self.context = context
        self.container = context.container
    }

    func save(_ ride: Ride) throws {
        let encodedPoints = try encoder.encode(ride.points)
        let id = ride.id
        // Upsert: update an existing record with the same id, else insert.
        let descriptor = FetchDescriptor<RideRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.startedAt = ride.startedAt
            existing.endedAt = ride.endedAt
            existing.distanceMeters = ride.summary.distanceMeters
            existing.activeDuration = ride.summary.activeDuration
            existing.averageSpeed = ride.summary.averageSpeedMetersPerSecond
            existing.encodedPoints = encodedPoints
            existing.syncStatusRaw = ride.syncStatus.rawValue
            existing.sharePublicly = ride.sharePublicly
        } else {
            context.insert(
                RideRecord(
                    id: ride.id,
                    startedAt: ride.startedAt,
                    endedAt: ride.endedAt,
                    distanceMeters: ride.summary.distanceMeters,
                    activeDuration: ride.summary.activeDuration,
                    averageSpeed: ride.summary.averageSpeedMetersPerSecond,
                    encodedPoints: encodedPoints,
                    syncStatusRaw: ride.syncStatus.rawValue,
                    sharePublicly: ride.sharePublicly
                )
            )
        }
        try context.save()
    }

    func allRides() throws -> [Ride] {
        let descriptor = FetchDescriptor<RideRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        // Skip (and log) undecodable records instead of throwing (Req 7.7).
        return records.compactMap { ride(from: $0) }
    }

    func ride(id: UUID) throws -> Ride? {
        let descriptor = FetchDescriptor<RideRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else {
            return nil
        }
        return ride(from: record)
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<RideRecord>(
            predicate: #Predicate { $0.id == id }
        )
        // Deleting a missing id is a safe no-op (Requirement 7.4).
        guard let record = try context.fetch(descriptor).first else {
            return
        }
        context.delete(record)
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: RideRecord.self)
        try context.save()
    }

    // MARK: Mapping

    /// Maps a record to a domain `Ride`, returning `nil` (after logging) if its
    /// encoded points cannot be decoded, so callers can skip it gracefully.
    private func ride(from record: RideRecord) -> Ride? {
        let points: [RoutePoint]
        do {
            points = try decoder.decode([RoutePoint].self, from: record.encodedPoints)
        } catch {
            Self.logger.error(
                "Skipping ride \(record.id, privacy: .public): points failed to decode (\(String(describing: error), privacy: .public))"
            )
            return nil
        }
        return Ride(
            id: record.id,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            points: points,
            summary: RideSummary(
                distanceMeters: record.distanceMeters,
                activeDuration: record.activeDuration,
                averageSpeedMetersPerSecond: record.averageSpeed
            ),
            // An unrecognized raw value falls back to `.localOnly` so a record
            // written by a newer build is never treated as something invalid.
            sharePublicly: record.sharePublicly,
            syncStatus: SyncStatus(rawValue: record.syncStatusRaw) ?? .localOnly
        )
    }
}
