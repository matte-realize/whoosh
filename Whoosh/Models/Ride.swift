import Foundation

/// A single recording session from start to stop.
///
/// The domain `Ride` is kept separate from the persisted record (`RideRecord`,
/// SwiftData) so view models and metrics operate on cheap, framework-free value
/// types; storage concerns never leak upward. Mapping happens only at the
/// repository boundary.
struct Ride: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var points: [RoutePoint]
    /// Recomputed on finalize from `points` and the accumulated active duration.
    var summary: RideSummary

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        points: [RoutePoint] = [],
        summary: RideSummary = .zero
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.summary = summary
    }
}
