import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure distance / average-speed / summary computations
/// (Requirements 6.2, 6.3, 6.4). Haversine expected values are hand-computed
/// against the same mean-Earth-radius constant the implementation uses
/// (6,371,000 m) with a stated tolerance.
struct RideMetricsTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func point(
        _ lat: Double,
        _ lon: Double,
        speed: Double = 5,
        accuracy: Double = 5
    ) -> RoutePoint {
        RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: epoch,
            speedMetersPerSecond: speed,
            horizontalAccuracyMeters: accuracy
        )
    }

    // MARK: distance

    @Test func emptyRouteHasZeroDistance() {
        #expect(RideMetrics.distanceMeters([]) == 0)
    }

    @Test func singlePointHasZeroDistance() {
        #expect(RideMetrics.distanceMeters([Self.point(42.36, -71.05)]) == 0)
    }

    @Test func twoPointsOneDegreeLongitudeAtEquator() {
        // Hand-computed: R * (π/180) = 6_371_000 * 0.01745329252 ≈ 111194.9266 m.
        let distance = RideMetrics.distanceMeters([
            Self.point(0, 0),
            Self.point(0, 1),
        ])
        #expect(abs(distance - 111_194.9266) < 0.1)
    }

    @Test func twoPointsOneDegreeLatitude() {
        // Same great-circle length as one degree of longitude at the equator.
        let distance = RideMetrics.distanceMeters([
            Self.point(0, 0),
            Self.point(1, 0),
        ])
        #expect(abs(distance - 111_194.9266) < 0.1)
    }

    @Test func multiPointRouteSumsSegments() {
        // Three Boston-area points; total hand-computed ≈ 276.5150 m
        // (138.2579 + 138.2571), tolerance 0.5 m.
        let distance = RideMetrics.distanceMeters([
            Self.point(42.3601, -71.0589),
            Self.point(42.3611, -71.0579),
            Self.point(42.3621, -71.0569),
        ])
        #expect(abs(distance - 276.5150) < 0.5)
    }

    // MARK: average speed

    @Test func averageSpeedIsDistanceOverDuration() {
        #expect(RideMetrics.averageSpeed(distanceMeters: 1000, activeDuration: 100) == 10)
    }

    @Test func averageSpeedZeroDurationIsZeroNotNaN() {
        let speed = RideMetrics.averageSpeed(distanceMeters: 1000, activeDuration: 0)
        #expect(speed == 0)
        #expect(!speed.isNaN)
    }

    @Test func averageSpeedNegativeDurationIsZero() {
        #expect(RideMetrics.averageSpeed(distanceMeters: 1000, activeDuration: -5) == 0)
    }

    // MARK: summary

    @Test func summaryForEmptyRouteIsAllZero() {
        let summary = RideMetrics.summary(points: [], activeDuration: 0)
        #expect(summary == .zero)
    }

    @Test func summaryForSinglePointHasZeroDistanceAndSpeed() {
        let summary = RideMetrics.summary(
            points: [Self.point(42.36, -71.05)],
            activeDuration: 60
        )
        #expect(summary.distanceMeters == 0)
        #expect(summary.activeDuration == 60)
        #expect(summary.averageSpeedMetersPerSecond == 0)
    }

    @Test func summaryComputesDistanceDurationAndSpeed() {
        let summary = RideMetrics.summary(
            points: [Self.point(0, 0), Self.point(0, 1)],
            activeDuration: 1000
        )
        #expect(abs(summary.distanceMeters - 111_194.9266) < 0.1)
        #expect(summary.activeDuration == 1000)
        let expectedSpeed = 111_194.9266 / 1000
        #expect(abs(summary.averageSpeedMetersPerSecond - expectedSpeed) < 0.001)
    }
}
