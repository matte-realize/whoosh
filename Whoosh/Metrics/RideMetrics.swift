import Foundation

/// Pure, framework-free ride metric computations — the testable heart of
/// Requirement 6. Lives in the Metrics layer (Models + Foundation only).
///
/// Distance uses the Haversine formula summed over consecutive point pairs.
/// Active duration is supplied by the caller (the view model knows pause spans);
/// metrics never infer duration from timestamps, so paused gaps can't inflate it.
enum RideMetrics {
    /// Mean Earth radius in meters used for the Haversine distance.
    static let earthRadiusMeters: Double = 6_371_000

    /// Total route distance in meters: the sum of Haversine segment lengths
    /// between consecutive points.
    ///
    /// Empty or single-point routes yield `0`.
    static func distanceMeters(_ points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<points.count {
            total += haversineMeters(points[index - 1], points[index])
        }
        return total
    }

    /// Average speed in meters/second, defined as distance divided by active
    /// duration. Returns `0` when `activeDuration <= 0` (no divide-by-zero,
    /// Requirement 6.4).
    static func averageSpeed(distanceMeters: Double, activeDuration: TimeInterval) -> Double {
        guard activeDuration > 0 else { return 0 }
        return distanceMeters / activeDuration
    }

    /// The full summary from a route and its (externally tracked) active
    /// duration. Edge cases (empty / single point / zero duration) all produce
    /// a sensible, finite summary rather than an error or NaN.
    static func summary(points: [RoutePoint], activeDuration: TimeInterval) -> RideSummary {
        let distance = distanceMeters(points)
        let average = averageSpeed(distanceMeters: distance, activeDuration: activeDuration)
        return RideSummary(
            distanceMeters: distance,
            activeDuration: activeDuration,
            averageSpeedMetersPerSecond: average
        )
    }

    /// Great-circle distance in meters between two route points.
    private static func haversineMeters(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let sinHalfLat = sin(dLat / 2)
        let sinHalfLon = sin(dLon / 2)
        let h = sinHalfLat * sinHalfLat
            + cos(lat1) * cos(lat2) * sinHalfLon * sinHalfLon
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return earthRadiusMeters * c
    }
}
