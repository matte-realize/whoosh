import Foundation
import Testing
@testable import Whoosh

/// Tests for the centralized US-customary formatting (Requirements 10.1/10.2),
/// including the 10-mile decimal boundary, the feet threshold, the 1-hour
/// duration boundary, and sane zero/large values. Output is fixed en_US so these
/// assertions hold regardless of the host locale.
///
/// Note: `@Test(arguments:)` literal arrays are evaluated in a nonisolated
/// context by the macro, so meter fixtures are written as pre-computed literals
/// (meters = miles × 1609.344) rather than referencing a shared constant.
struct FormattersTests {
    // MARK: Miles — decimal policy and boundary

    @Test(arguments: [
        (0.0, "0.00 mi"),
        (1_609.344, "1.00 mi"),          // 1 mi
        (8_046.72, "5.00 mi"),           // 5 mi, under 10 → 2 decimals
        (16_077.346_56, "9.99 mi"),      // 9.99 mi, just under boundary → 2 decimals
        (16_093.44, "10.0 mi"),          // 10 mi, at boundary → 1 decimal
        (19_859.304_96, "12.3 mi"),      // 12.34 mi, above → 1 decimal
        (1_986_735.168, "1,234.5 mi"),   // 1234.5 mi, large, grouped, 1 decimal
    ])
    func milesFormatting(meters: Double, expected: String) {
        #expect(Formatters.miles(fromMeters: meters) == expected)
    }

    @Test func negativeDistanceClampsToZeroMiles() {
        #expect(Formatters.miles(fromMeters: -100) == "0.00 mi")
    }

    // MARK: Feet

    @Test(arguments: [
        (0.0, "0 ft"),
        (30.48, "100 ft"),
        (80.4672, "264 ft"),
    ])
    func feetFormatting(meters: Double, expected: String) {
        #expect(Formatters.feet(fromMeters: meters) == expected)
    }

    // MARK: Short distance (feet under 0.1 mi, miles otherwise)

    @Test func shortDistanceUsesFeetUnderTenthMile() {
        // 0.05 mi ≈ 80.47 m → feet.
        #expect(Formatters.shortDistance(fromMeters: 80.4672) == "264 ft")
    }

    @Test func shortDistanceUsesMilesAtOrAboveTenthMile() {
        // Exactly 0.1 mi (160.9344 m) → miles, two decimals.
        #expect(Formatters.shortDistance(fromMeters: 160.9344) == "0.10 mi")
    }

    @Test func shortDistanceZeroIsFeet() {
        #expect(Formatters.shortDistance(fromMeters: 0) == "0 ft")
    }

    // MARK: Speed (mph, one decimal)

    @Test(arguments: [
        (0.0, "0.0 mph"),
        (10.0, "22.4 mph"),       // 10 m/s ≈ 22.369 → 22.4
        (4.4704, "10.0 mph"),     // ~10 mph
    ])
    func mphFormatting(metersPerSecond: Double, expected: String) {
        #expect(Formatters.mph(fromMetersPerSecond: metersPerSecond) == expected)
    }

    @Test func negativeSpeedClampsToZero() {
        #expect(Formatters.mph(fromMetersPerSecond: -3) == "0.0 mph")
    }

    // MARK: Duration — m:ss under an hour, h:mm:ss at or above

    @Test(arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (65.0, "1:05"),
        (599.0, "9:59"),
        (3599.0, "59:59"),        // just under an hour
        (3600.0, "1:00:00"),      // boundary → h:mm:ss
        (3661.0, "1:01:01"),
        (36_000.0, "10:00:00"),   // large
    ])
    func durationFormatting(seconds: TimeInterval, expected: String) {
        #expect(Formatters.duration(seconds) == expected)
    }

    @Test func negativeDurationClampsToZero() {
        #expect(Formatters.duration(-42) == "0:00")
    }

    @Test func durationTruncatesFractionalSeconds() {
        #expect(Formatters.duration(65.9) == "1:05")
    }
}
