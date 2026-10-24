import Foundation

/// Aggregated numbers for the current week's Home dashboard (Requirement 13.4).
///
/// Pure value type in the Metrics layer; `distancePerWeekday` is always length 7
/// with index 0 = Monday … index 6 = Sunday, distance in meters.
struct WeeklyStats: Equatable, Sendable {
    let totalDistanceMeters: Double
    let rideCount: Int
    let totalActiveDuration: TimeInterval
    /// Monday…Sunday (index 0 = Monday); distance in meters per weekday. Length 7.
    let distancePerWeekday: [Double]

    /// A zeroed week (no rides) with an empty 7-bar chart.
    static let empty = WeeklyStats(
        totalDistanceMeters: 0,
        rideCount: 0,
        totalActiveDuration: 0,
        distancePerWeekday: Array(repeating: 0, count: 7)
    )
}
