import Foundation
import Testing
@testable import Whoosh

/// Test-first coverage for the pure weekly aggregation (Requirements 13.4/13.5/
/// 13.6). All tests inject a fixed-timezone `Calendar` (America/New_York,
/// `firstWeekday = Monday`) and an explicit `now`, so results are deterministic
/// and independent of the host machine.
struct WeeklyStatsCalculatorTests {
    /// America/New_York with Monday as the first weekday, matching the dashboard.
    private static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        // Force-unwrap avoided: fall back to UTC if the id is somehow unknown.
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private static func date(_ epoch: Double) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    private static func ride(
        startedAt: Date,
        distance: Double,
        duration: TimeInterval = 600
    ) -> Ride {
        Ride(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            points: [],
            summary: RideSummary(
                distanceMeters: distance,
                activeDuration: duration,
                averageSpeedMetersPerSecond: duration > 0 ? distance / duration : 0
            )
        )
    }

    // Reference epochs (America/New_York), computed independently.
    private static let monJun2_0900 = date(1_748_869_200) // Mon Jun 2 2025 09:00
    private static let wedJun4_1500 = date(1_749_063_600) // Wed Jun 4 2025 15:00
    private static let sunJun8_2300 = date(1_749_438_000) // Sun Jun 8 2025 23:00
    private static let monJun2_0000 = date(1_748_836_800) // Mon Jun 2 2025 00:00 (week start)
    private static let nextMonJun9_0000 = date(1_749_441_600) // Mon Jun 9 2025 00:00 (next week start)
    private static let prevSunJun1_1200 = date(1_748_793_600) // Sun Jun 1 2025 12:00 (prior week)
    // nowDuringJunWeek: any instant inside the Jun 2–8 week.
    private static let nowJunWeek = wedJun4_1500

    // DST week (spring forward Sun Mar 9 2025).
    private static let monMar3_0000 = date(1_740_978_000) // Mon Mar 3 2025 00:00
    private static let monMar3_1201 = date(1_741_021_260) // Mon Mar 3 2025 12:01
    private static let sunMar9_1200 = date(1_741_536_000) // Sun Mar 9 2025 12:00
    private static let nextMonMar10_0000 = date(1_741_579_200) // Mon Mar 10 2025 00:00
    private static let nowMarWeek = date(1_741_280_000) // Thu Mar 6 2025, inside the DST week

    @Test func noRidesReturnsEmpty() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats == .empty)
        #expect(stats.distancePerWeekday.count == 7)
    }

    @Test func ridesOutsideCurrentWeekAreIgnored() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [Self.ride(startedAt: Self.prevSunJun1_1200, distance: 5000)],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats == .empty)
    }

    @Test func rideOnWeekStartBoundaryIsIncluded() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [Self.ride(startedAt: Self.monJun2_0000, distance: 1000)],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats.rideCount == 1)
        #expect(stats.totalDistanceMeters == 1000)
        // Monday bucket.
        #expect(stats.distancePerWeekday[0] == 1000)
    }

    @Test func rideOnNextWeekStartBoundaryIsExcluded() {
        // Half-open interval: the next week's start (Mon Jun 9 00:00) is excluded.
        let stats = WeeklyStatsCalculator.compute(
            rides: [Self.ride(startedAt: Self.nextMonJun9_0000, distance: 1000)],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats == .empty)
    }

    @Test func bucketsRidesByWeekdayMondayToSunday() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [
                Self.ride(startedAt: Self.monJun2_0900, distance: 1000, duration: 300),
                Self.ride(startedAt: Self.wedJun4_1500, distance: 2000, duration: 600),
                Self.ride(startedAt: Self.sunJun8_2300, distance: 3000, duration: 900),
            ],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats.rideCount == 3)
        #expect(stats.totalDistanceMeters == 6000)
        #expect(stats.totalActiveDuration == 1800)
        #expect(stats.distancePerWeekday[0] == 1000) // Monday
        #expect(stats.distancePerWeekday[2] == 2000) // Wednesday
        #expect(stats.distancePerWeekday[6] == 3000) // Sunday
        // All other buckets zero.
        #expect(stats.distancePerWeekday[1] == 0)
        #expect(stats.distancePerWeekday[3] == 0)
        #expect(stats.distancePerWeekday[4] == 0)
        #expect(stats.distancePerWeekday[5] == 0)
    }

    @Test func zeroDistanceRideStillCountsAndBuckets() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [Self.ride(startedAt: Self.wedJun4_1500, distance: 0, duration: 120)],
            now: Self.nowJunWeek,
            calendar: Self.calendar()
        )
        #expect(stats.rideCount == 1)
        #expect(stats.totalDistanceMeters == 0)
        #expect(stats.totalActiveDuration == 120)
        #expect(stats.distancePerWeekday[2] == 0) // Wednesday bucket present but 0
        #expect(!stats.totalDistanceMeters.isNaN)
    }

    @Test func weekSpanningDSTIncludesFullMondayToSunday() {
        // Week Mon Mar 3 .. Sun Mar 9 2025 spans the spring-forward transition.
        // Both the Monday-start boundary ride and the Sunday ride (after the
        // DST change) must be inside the week; the next Monday is excluded.
        let stats = WeeklyStatsCalculator.compute(
            rides: [
                Self.ride(startedAt: Self.monMar3_1201, distance: 1500),
                Self.ride(startedAt: Self.sunMar9_1200, distance: 2500),
                Self.ride(startedAt: Self.nextMonMar10_0000, distance: 9999), // excluded
            ],
            now: Self.nowMarWeek,
            calendar: Self.calendar()
        )
        #expect(stats.rideCount == 2)
        #expect(stats.totalDistanceMeters == 4000)
        #expect(stats.distancePerWeekday[0] == 1500) // Monday
        #expect(stats.distancePerWeekday[6] == 2500) // Sunday
    }

    @Test func dstWeekStartBoundaryIncluded() {
        let stats = WeeklyStatsCalculator.compute(
            rides: [Self.ride(startedAt: Self.monMar3_0000, distance: 700)],
            now: Self.nowMarWeek,
            calendar: Self.calendar()
        )
        #expect(stats.rideCount == 1)
        #expect(stats.distancePerWeekday[0] == 700)
    }
}
