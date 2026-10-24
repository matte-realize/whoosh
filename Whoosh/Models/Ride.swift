import Foundation

/// A single recording session from start to stop.
///
/// The domain `Ride` is kept separate from the persisted record (`RideRecord`,
/// SwiftData) so view models and metrics operate on cheap, framework-free value
/// types; storage concerns never leak upward. Mapping happens only at the
/// repository boundary.
struct Ride: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var points: [RoutePoint]
    /// Recomputed on finalize from `points` and the accumulated active duration.
    var summary: RideSummary
    /// The cloud-sync state of the ride (Requirement 12). Defaults to
    /// `.localOnly` so every existing caller and stored ride is unaffected
    /// until opt-in sync runs; the `SyncCoordinator` advances it to `.pending`
    /// or `.synced`.
    var syncStatus: SyncStatus

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        points: [RoutePoint] = [],
        summary: RideSummary = .zero,
        syncStatus: SyncStatus = .localOnly
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.summary = summary
        self.syncStatus = syncStatus
    }
}
