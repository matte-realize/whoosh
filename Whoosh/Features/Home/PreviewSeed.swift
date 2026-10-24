import Foundation

/// Preview-only helpers that seed an in-memory repository and a
/// `FakeLocationTracker` so Home previews render with realistic data without
/// touching Core Location or persistence. Not used by the shipping app paths
/// (the composition root injects the real services).
enum PreviewSeed {
    /// A `HomeViewModel` for previews, optionally seeded with a few finished
    /// rides and with a chosen authorization status.
    static func homeViewModel(
        seeded: Bool,
        status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> HomeViewModel {
        let now = Date(timeIntervalSince1970: 1_729_784_400) // Sat, Oct 24 2026
        let repository = InMemoryRideRepository(rides: seeded ? rides(now: now) : [])
        let tracker = FakeLocationTracker(authorizationStatus: status)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        return HomeViewModel(
            repository: repository,
            clock: FixedClock(fixed: now),
            calendar: calendar,
            tracker: tracker
        )
    }

    /// A few finished rides spread across the current week for the dashboard.
    static func rides(now: Date) -> [Ride] {
        [
            makeRide(
                start: now.addingTimeInterval(-2 * 86_400 + 3_600),
                distance: 8_561, duration: 1_458, avgSpeed: 5.87
            ),
            makeRide(
                start: now.addingTimeInterval(-4 * 86_400 + 7_200),
                distance: 6_195, duration: 1_180, avgSpeed: 5.25
            ),
            makeRide(
                start: now.addingTimeInterval(-6 * 86_400 + 1_800),
                distance: 5_200, duration: 980, avgSpeed: 5.31
            ),
        ]
    }

    private static func makeRide(
        start: Date,
        distance: Double,
        duration: TimeInterval,
        avgSpeed: Double
    ) -> Ride {
        let points: [RoutePoint] = (0..<8).map { i in
            let lat: Double = 42.36 + Double(i) * 0.0011
            let lon: Double = -71.09 + Double(i) * 0.0013
            let time = start.addingTimeInterval(Double(i) * 10)
            return RoutePoint(
                latitude: lat,
                longitude: lon,
                timestamp: time,
                speedMetersPerSecond: avgSpeed,
                horizontalAccuracyMeters: 5
            )
        }
        return Ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            points: points,
            summary: RideSummary(
                distanceMeters: distance,
                activeDuration: duration,
                averageSpeedMetersPerSecond: avgSpeed
            )
        )
    }
}

/// A trivial `Clock` returning a fixed `now`, for deterministic previews.
/// Scheduling is a no-op (previews don't exercise timers).
private struct FixedClock: Clock {
    let fixed: Date
    func now() -> Date { fixed }
    @discardableResult
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        NoopCancellable()
    }

    private struct NoopCancellable: Cancellable {
        func cancel() {}
    }
}
