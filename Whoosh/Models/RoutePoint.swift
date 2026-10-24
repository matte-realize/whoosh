import Foundation

/// One GPS sample recorded during a ride.
///
/// Stored in SI units: coordinates in degrees, timestamp as an absolute `Date`,
/// speed in meters/second (negative when unknown, matching Core Location's
/// convention), and horizontal accuracy in meters. Conversion to US customary
/// units happens only in the formatting layer.
///
/// A pure value type with no framework dependency so metrics and tests can
/// construct fixtures cheaply (layering table: Models import Foundation only).
struct RoutePoint: Equatable, Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    /// Instantaneous speed in meters/second; `< 0` when unknown.
    let speedMetersPerSecond: Double
    /// Horizontal accuracy radius in meters; larger is worse.
    let horizontalAccuracyMeters: Double

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        speedMetersPerSecond: Double,
        horizontalAccuracyMeters: Double
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.speedMetersPerSecond = speedMetersPerSecond
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}
