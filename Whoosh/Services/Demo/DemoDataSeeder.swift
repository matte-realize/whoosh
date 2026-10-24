import Foundation

/// Seeds and removes demo sample data so Home, History, and the weekly chart
/// look populated for a demo, then cleanly clears it afterwards (demo-mode spec
/// task 7; Requirements 7.1, 7.2, 7.3, 7.5, 7.6).
///
/// Every seeded ride is a finished **demo ride** (`isDemo == true`), so it is
/// excluded from sync and from the Home This-Week stats (O-DM2). `removeDemo()`
/// deletes **only** demo-flagged rides — real rides are never touched.
///
/// Dates are built relative to the injected `Clock`'s "now" so the seeded rides
/// fall across the current and prior weeks deterministically (testable without a
/// device). The repository is injected behind the `RideRepository` protocol, so
/// the seeder is unit-tested against `InMemoryRideRepository`.
///
/// `@MainActor` because `RideRepository` implementations run on the main actor
/// in this project (default MainActor isolation; SwiftData's `ModelContext` is
/// main-actor here).
@MainActor
final class DemoDataSeeder {
    private let repository: RideRepository
    private let clock: Clock

    init(repository: RideRepository, clock: Clock) {
        self.repository = repository
        self.clock = clock
    }

    /// How many demo rides are currently stored. Used on re-seed to report the
    /// existing count and offer remove-first rather than silently duplicating
    /// (O-DM7, Requirement 7.3).
    func existingDemoCount() throws -> Int {
        try repository.allRides().filter(\.isDemo).count
    }

    /// Insert a small set of realistic finished demo rides. Returns the number
    /// inserted. Pass `removingExisting: true` to clear existing demo rides
    /// first so a re-seed does not create confusing duplicates (O-DM7).
    @discardableResult
    func seed(removingExisting: Bool = false) throws -> Int {
        if removingExisting {
            try removeDemo()
        }
        let rides = Self.sampleRides(now: clock.now())
        for ride in rides {
            try repository.save(ride)
        }
        return rides.count
    }

    /// Delete **only** demo-flagged rides, leaving every real ride untouched
    /// (real deletion through the repository, Requirement 7.2). Returns the
    /// number removed.
    @discardableResult
    func removeDemo() throws -> Int {
        let demoIDs = try repository.allRides().filter(\.isDemo).map(\.id)
        for id in demoIDs {
            try repository.delete(id: id)
        }
        return demoIDs.count
    }

    // MARK: - Sample data (pure)

    /// Build the fixed set of demo rides relative to `now`. Varied dates across
    /// the current and prior two weeks, varied distances/durations; at least one
    /// carries a real route (a short Boston loop). Pure so it is trivially
    /// testable.
    static func sampleRides(now: Date) -> [Ride] {
        // (daysAgo, distanceMeters, activeDuration, avgSpeed m/s, hasRoute)
        let specs: [(Int, Double, TimeInterval, Double, Bool)] = [
            (1, 8_561, 1_458, 5.87, true),
            (3, 6_195, 1_180, 5.25, true),
            (5, 12_740, 2_410, 5.29, false),
            (8, 4_300, 820, 5.24, true),
            (12, 15_980, 3_010, 5.31, false),
            (17, 7_050, 1_340, 5.26, true),
        ]
        let day: TimeInterval = 86_400
        return specs.map { daysAgo, distance, duration, avgSpeed, hasRoute in
            // Mid-morning on the target day, give or take, for a plausible time.
            let start = now.addingTimeInterval(-Double(daysAgo) * day + 9 * 3_600)
            let points = hasRoute ? bostonLoopPoints(from: start, avgSpeed: avgSpeed) : []
            return Ride(
                startedAt: start,
                endedAt: start.addingTimeInterval(duration),
                points: points,
                summary: RideSummary(
                    distanceMeters: distance,
                    activeDuration: duration,
                    averageSpeedMetersPerSecond: avgSpeed
                ),
                isDemo: true
            )
        }
    }

    /// A short, realistic Charles River / Mass Ave loop around Boston so at
    /// least one seeded ride draws a route on the map.
    private static func bostonLoopPoints(from start: Date, avgSpeed: Double) -> [RoutePoint] {
        (0..<10).map { i in
            RoutePoint(
                latitude: 42.3601 + Double(i) * 0.0012,
                longitude: -71.0942 + Double(i) * 0.0014,
                timestamp: start.addingTimeInterval(Double(i) * 12),
                speedMetersPerSecond: avgSpeed,
                horizontalAccuracyMeters: 5
            )
        }
    }
}
