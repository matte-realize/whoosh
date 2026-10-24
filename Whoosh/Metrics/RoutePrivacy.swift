import Foundation

/// Privacy-zone trimming applied to a route *before* upload (Requirement 12.5).
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). Removes the
/// first and last `meters` of the route — measured as cumulative Haversine
/// distance from each end via `RideMetrics` — so the rider's home or work isn't
/// exposed on the Whoosh map. The **local** route is never affected: `trim`
/// returns a new array and never mutates its input, and the `SyncCoordinator`
/// only trims the copy it hands to `RideSyncService.upload`.
///
/// Behavior:
/// - A route whose total length is ≤ `2 × meters` has no safe interior to keep,
///   so `trim` returns an empty array (nothing is uploaded rather than exposing
///   an endpoint).
/// - Empty and single-point routes return empty.
/// - Points are kept only while their cumulative distance from the start lies
///   strictly inside the `(meters, total − meters)` window, so both privacy
///   zones are fully removed. The kept points stay in their original order and
///   form a contiguous slice of the input.
enum RoutePrivacy {
    /// The default privacy-zone length trimmed from each end (~0.1 mi).
    static let defaultTrimMeters: Double = 160

    /// Returns the route with its first and last `meters` removed. See the type
    /// doc for the full contract. Never mutates `points`.
    static func trim(points: [RoutePoint], meters: Double = defaultTrimMeters) -> [RoutePoint] {
        guard meters > 0 else { return points }
        guard points.count > 1 else { return [] }

        let total = RideMetrics.distanceMeters(points)
        // No interior survives a trim from both ends. The small epsilon treats
        // a route that is essentially exactly `2 × meters` as having no safe
        // interior, independent of floating-point rounding in the Haversine sum.
        let epsilon = 0.01
        guard total > 2 * meters + epsilon else { return [] }

        let lowerBound = meters + epsilon
        let upperBound = total - meters - epsilon
        var cumulative: Double = 0
        var kept: [RoutePoint] = []
        kept.reserveCapacity(points.count)

        for index in points.indices {
            if index > 0 {
                cumulative += RideMetrics.distanceMeters(
                    [points[index - 1], points[index]]
                )
            }
            // Strictly inside the window: both privacy zones are fully removed,
            // and an exactly-2×-trim route keeps nothing.
            if cumulative > lowerBound, cumulative < upperBound {
                kept.append(points[index])
            }
        }
        return kept
    }
}
