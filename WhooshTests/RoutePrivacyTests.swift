import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `RoutePrivacy.trim(points:meters:)` privacy-zone function
/// (Requirement 12.5). Written test-first.
///
/// `trim` removes the first and last `meters` of the route (by cumulative
/// Haversine distance) before upload so the rider's home/work isn't exposed.
/// The local route is never modified — only the returned array is trimmed.
struct RoutePrivacyTests {
    /// Builds a straight west→east line of points spaced ~`spacingMeters`
    /// apart at a fixed latitude, so cumulative distance is predictable.
    private static func line(count: Int, spacingMeters: Double, lat: Double = 0) -> [RoutePoint] {
        // At the equator, one degree of longitude ≈ 111_320 m. Using lat = 0
        // keeps the longitude→meters factor at its maximum and simplest.
        let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180
        let degPerStep = spacingMeters / metersPerDegreeLon
        return (0..<count).map { i in
            RoutePoint(
                latitude: lat,
                longitude: Double(i) * degPerStep,
                timestamp: Date(timeIntervalSince1970: Double(i)),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
    }

    // MARK: edge cases

    @Test func emptyRouteReturnsEmpty() {
        #expect(RoutePrivacy.trim(points: [], meters: 160).isEmpty)
    }

    @Test func singlePointReturnsEmpty() {
        let points = Self.line(count: 1, spacingMeters: 100)
        #expect(RoutePrivacy.trim(points: points, meters: 160).isEmpty)
    }

    @Test func routeShorterThanTwiceTrimReturnsEmpty() {
        // 3 points × 100 m spacing = ~200 m total, which is < 2 × 160 m = 320 m.
        let points = Self.line(count: 3, spacingMeters: 100)
        #expect(RoutePrivacy.trim(points: points, meters: 160).isEmpty)
    }

    @Test func routeExactlyTwiceTrimReturnsEmpty() {
        // Total ≈ 320 m == 2 × 160 m. There is no interior left to keep, so the
        // half-open trim from both ends yields nothing.
        let points = Self.line(count: 5, spacingMeters: 80) // 4 segments × 80 = 320 m
        let trimmed = RoutePrivacy.trim(points: points, meters: 160)
        #expect(trimmed.isEmpty)
    }

    // MARK: normal trimming

    @Test func normalRouteKeepsInteriorAndDropsEnds() {
        // 21 points × 100 m = 2000 m total. Trim 160 m from each end.
        let points = Self.line(count: 21, spacingMeters: 100)
        let trimmed = RoutePrivacy.trim(points: points, meters: 160)

        #expect(!trimmed.isEmpty)
        // Fewer points than the original (ends removed).
        #expect(trimmed.count < points.count)

        // Every kept point lies strictly inside the [160, 1840] distance window.
        let total = RideMetrics.distanceMeters(points)
        for kept in trimmed {
            // distance from start to this kept point, via the original route
            guard let idx = points.firstIndex(of: kept) else {
                Issue.record("trimmed point not found in original route")
                continue
            }
            let fromStart = RideMetrics.distanceMeters(Array(points[0...idx]))
            #expect(fromStart >= 160 - 0.001)
            #expect(fromStart <= total - 160 + 0.001)
        }
    }

    @Test func trimmedRouteIsContiguousSubsequenceInOrder() {
        let points = Self.line(count: 21, spacingMeters: 100)
        let trimmed = RoutePrivacy.trim(points: points, meters: 160)

        // The kept points must be a contiguous slice of the original in order.
        guard let first = trimmed.first, let firstIdx = points.firstIndex(of: first) else {
            Issue.record("expected a non-empty trimmed route")
            return
        }
        let expected = Array(points[firstIdx..<(firstIdx + trimmed.count)])
        #expect(trimmed == expected)
    }

    // MARK: input is never mutated

    @Test func inputRouteIsNotMutated() {
        let points = Self.line(count: 21, spacingMeters: 100)
        let snapshot = points
        _ = RoutePrivacy.trim(points: points, meters: 160)
        // `points` is a value-type array; prove the function returns a new array
        // and leaves the caller's copy identical.
        #expect(points == snapshot)
    }

    @Test func defaultTrimDistanceIs160Meters() {
        let points = Self.line(count: 21, spacingMeters: 100)
        let explicit = RoutePrivacy.trim(points: points, meters: 160)
        let defaulted = RoutePrivacy.trim(points: points)
        #expect(explicit == defaulted)
    }

    @Test func zeroTrimKeepsWholeRoute() {
        let points = Self.line(count: 10, spacingMeters: 100)
        let trimmed = RoutePrivacy.trim(points: points, meters: 0)
        #expect(trimmed == points)
    }
}
