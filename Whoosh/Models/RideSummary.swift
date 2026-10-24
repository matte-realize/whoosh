import Foundation

/// The computed result of a finished (or in-progress) ride.
///
/// All values are SI: distance in meters, duration in seconds, speed in
/// meters/second. `activeDuration` excludes paused intervals (see the
/// active-duration definition in the design / Requirement 3.8). Pure value type
/// so `RideMetrics` can produce it without any framework dependency.
struct RideSummary: Equatable, Hashable, Codable, Sendable {
    let distanceMeters: Double
    /// Active (moving) time in seconds; excludes paused spans.
    let activeDuration: TimeInterval
    let averageSpeedMetersPerSecond: Double

    init(
        distanceMeters: Double,
        activeDuration: TimeInterval,
        averageSpeedMetersPerSecond: Double
    ) {
        self.distanceMeters = distanceMeters
        self.activeDuration = activeDuration
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
    }

    /// An all-zero summary, used for rides finalized with zero acceptable
    /// points (Requirement 6.3 / 3.7).
    static let zero = RideSummary(
        distanceMeters: 0,
        activeDuration: 0,
        averageSpeedMetersPerSecond: 0
    )
}
