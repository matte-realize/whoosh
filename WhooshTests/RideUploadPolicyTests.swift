import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `RideUploadPolicy` (task 28d, Requirements 12.5,
/// 12.18–12.21). The policy trims → thins → validates → maps a `Ride` into the
/// `rides` row, and never makes a network request.
struct RideUploadPolicyTests {
    // A route long enough to survive a 160 m trim and keep a clear interior.
    // ~100 m spacing along the equator keeps the math simple.
    private static let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180

    private static func straightRoute(
        points count: Int,
        spacingMeters: Double = 100,
        startedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> [RoutePoint] {
        let degPerStep = spacingMeters / metersPerDegreeLon
        return (0..<count).map { i in
            RoutePoint(
                latitude: 0,
                longitude: Double(i) * degPerStep,
                timestamp: startedAt.addingTimeInterval(Double(i)),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
    }

    private static func ride(
        id: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endedAt: Date = Date(timeIntervalSince1970: 1_700_001_200),
        points: [RoutePoint],
        distanceMeters: Double = 2_000,
        activeDuration: TimeInterval = 1_200,
        avgSpeed: Double = 1.67,
        sharePublicly: Bool = false
    ) -> Ride {
        Ride(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            points: points,
            summary: RideSummary(
                distanceMeters: distanceMeters,
                activeDuration: activeDuration,
                averageSpeedMetersPerSecond: avgSpeed
            ),
            sharePublicly: sharePublicly
        )
    }

    private let appVersion = "1.0.0"

    // MARK: < 2 points → local only

    @Test func rideWithFewerThanTwoPointsAfterTrimStaysLocalOnly() throws {
        // Only 2 points 100 m apart; a 160 m trim from each end removes both.
        let ride = Self.ride(points: Self.straightRoute(points: 2))
        let outcome = RideUploadPolicy.prepare(ride, appVersion: appVersion)
        #expect(outcome == .skipLocalOnly)
    }

    @Test func emptyRouteStaysLocalOnly() throws {
        let ride = Self.ride(points: [])
        let outcome = RideUploadPolicy.prepare(ride, appVersion: appVersion)
        #expect(outcome == .skipLocalOnly)
    }

    // MARK: demo ride skipped

    @Test func demoRideIsNeverUploaded() throws {
        let ride = Self.ride(points: Self.straightRoute(points: 50))
        let outcome = RideUploadPolicy.prepare(ride, appVersion: appVersion, isDemo: true)
        #expect(outcome == .skipLocalOnly)
    }

    // MARK: thinning

    @Test func thinsToAtMostTenThousandPointsKeepingEndpoints() throws {
        // 25,000 points, 10 m spacing → > 10,000 after trim; must thin.
        let route = Self.straightRoute(points: 25_000, spacingMeters: 10)
        let ride = Self.ride(points: route, distanceMeters: 100_000, avgSpeed: 5)
        guard case let .upload(row) = RideUploadPolicy.prepare(ride, appVersion: appVersion) else {
            Issue.record("expected .upload")
            return
        }
        let coords = try #require(row.route.coordinates)
        #expect(coords.count <= 10_000)
        #expect(coords.count >= 2)
    }

    // MARK: limit violations → failed, no request

    @Test func distanceOverLimitMarksFailed() throws {
        let ride = Self.ride(points: Self.straightRoute(points: 50), distanceMeters: 1_000_001)
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    @Test func activeDurationOverFortyEightHoursMarksFailed() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ride = Self.ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(172_801),
            points: Self.straightRoute(points: 50, startedAt: start),
            activeDuration: 172_801
        )
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    @Test func activeDurationExceedingElapsedMarksFailed() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // elapsed = 100 s but active = 1000 s → violates the elapsed+1 check.
        let ride = Self.ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(100),
            points: Self.straightRoute(points: 50, startedAt: start),
            activeDuration: 1_000
        )
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    @Test func avgSpeedOverLimitMarksFailed() throws {
        let ride = Self.ride(points: Self.straightRoute(points: 50), avgSpeed: 41)
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    @Test func endedMoreThanFortyEightHoursAfterStartMarksFailed() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let ride = Self.ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(172_800 + 5),
            points: Self.straightRoute(points: 50, startedAt: start),
            activeDuration: 1_200
        )
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    @Test func appVersionOverThirtyTwoCharsMarksFailed() throws {
        let ride = Self.ride(points: Self.straightRoute(points: 50))
        let longVersion = String(repeating: "v", count: 33)
        #expect(RideUploadPolicy.prepare(ride, appVersion: longVersion) == .markFailed)
    }

    @Test func outOfRangeCoordinateMarksFailed() throws {
        var route = Self.straightRoute(points: 50)
        route[25] = RoutePoint(
            latitude: 200, // invalid
            longitude: 0,
            timestamp: route[25].timestamp,
            speedMetersPerSecond: 5,
            horizontalAccuracyMeters: 5
        )
        let ride = Self.ride(points: route)
        #expect(RideUploadPolicy.prepare(ride, appVersion: appVersion) == .markFailed)
    }

    // MARK: golden JSON row mapping

    @Test func goldenJSONRowMappingPinsColumnsAndCoordinateOrder() throws {
        // A tiny deterministic route whose trimmed interior is well-defined.
        // 400 m spacing, 5 points → total 1600 m; trim 160 m each end keeps the
        // interior points. lon increases; lat is a small nonzero so [lon,lat]
        // order is unambiguous.
        let start = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let end = Date(timeIntervalSince1970: 1_700_001_200)
        let degPerStepLon = 400 / Self.metersPerDegreeLon
        let route = (0..<5).map { i in
            RoutePoint(
                latitude: 42.0,
                longitude: -71.0 + Double(i) * degPerStepLon,
                timestamp: start.addingTimeInterval(Double(i) * 10),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
        let ride = Ride(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            startedAt: start,
            endedAt: end,
            points: route,
            summary: RideSummary(
                distanceMeters: 1_600,
                activeDuration: 1_000,
                averageSpeedMetersPerSecond: 1.6
            ),
            sharePublicly: true
        )

        guard case let .upload(row) = RideUploadPolicy.prepare(ride, appVersion: "1.0.0") else {
            Issue.record("expected .upload")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(row)
        let json = try #require(String(data: data, encoding: .utf8))

        // Exact column names from the migration (no user_id / created_at).
        #expect(json.contains("\"id\":\"11111111-2222-3333-4444-555555555555\""))
        #expect(json.contains("\"started_at\":\"2023-11-14T22:13:20Z\""))
        #expect(json.contains("\"ended_at\":\"2023-11-14T22:33:20Z\""))
        #expect(json.contains("\"distance_m\":1600"))
        #expect(json.contains("\"active_duration_s\":1000"))
        #expect(json.contains("\"avg_speed_mps\":1.6"))
        #expect(json.contains("\"app_version\":\"1.0.0\""))
        #expect(json.contains("\"share_publicly\":true"))
        #expect(json.contains("\"type\":\"LineString\""))
        #expect(!json.contains("user_id"))
        #expect(!json.contains("created_at"))

        // GeoJSON [lon, lat] order: lon (-71.x) before lat (42.0).
        let coords = try #require(row.route.coordinates)
        #expect(coords.count >= 2)
        for pair in coords {
            #expect(pair.count == 2)
            #expect(pair[0] < 0)   // longitude ~ -71
            #expect(pair[1] == 42) // latitude
        }
    }

    @Test func routeEncodesAsLineStringWithLonLatPairs() throws {
        let ride = Self.ride(points: Self.straightRoute(points: 50))
        guard case let .upload(row) = RideUploadPolicy.prepare(ride, appVersion: appVersion) else {
            Issue.record("expected .upload")
            return
        }
        #expect(row.route.type == "LineString")
        let coords = try #require(row.route.coordinates)
        #expect(coords.allSatisfy { $0.count == 2 })
    }
}
