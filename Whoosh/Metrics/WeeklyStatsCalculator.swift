import Foundation

/// Pure, framework-free aggregation of finished rides into the current week's
/// dashboard numbers (Requirement 13.4/13.5/13.6). The calendar and `now` are
/// injected so the result is fully deterministic and testable (no hidden
/// `Date()` or `Calendar.current`), and DST transitions are handled by
/// `Calendar` date math rather than assuming 24-hour days.
enum WeeklyStatsCalculator {
    /// Aggregate `rides` into stats for the week containing `now`.
    ///
    /// The current week is the half-open interval `[startOfWeek, startOfWeek +
    /// 7 days)` derived from `calendar` and `now`. Rides whose `startedAt` falls
    /// outside that interval are ignored; a ride exactly on the week start is
    /// included and one exactly on the next week's start is excluded. Each
    /// included ride is bucketed into its weekday (Mon→Sun). Distance and active
    /// duration come from each ride's finalized summary; zero-distance rides
    /// still count toward `rideCount` and their weekday bucket.
    static func compute(rides: [Ride], now: Date, calendar: Calendar) -> WeeklyStats {
        guard let weekInterval = weekInterval(containing: now, calendar: calendar) else {
            return .empty
        }

        var totalDistance: Double = 0
        var totalDuration: TimeInterval = 0
        var count = 0
        var perWeekday = Array(repeating: 0.0, count: 7)

        for ride in rides {
            let started = ride.startedAt
            // Half-open interval: [start, end).
            guard started >= weekInterval.start, started < weekInterval.end else {
                continue
            }
            guard let index = mondayBasedIndex(for: started, calendar: calendar) else {
                continue
            }

            let distance = ride.summary.distanceMeters
            totalDistance += distance
            totalDuration += ride.summary.activeDuration
            count += 1
            perWeekday[index] += distance
        }

        return WeeklyStats(
            totalDistanceMeters: totalDistance,
            rideCount: count,
            totalActiveDuration: totalDuration,
            distancePerWeekday: perWeekday
        )
    }

    /// The half-open `[start, end)` interval for the week containing `date`.
    private static func weekInterval(
        containing date: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }
        // `DateInterval.end` is already the exclusive upper bound.
        return (interval.start, interval.end)
    }

    /// Weekday index with Monday = 0 … Sunday = 6, independent of the calendar's
    /// `firstWeekday`. Returns `nil` only if the calendar yields no weekday.
    private static func mondayBasedIndex(for date: Date, calendar: Calendar) -> Int? {
        // Calendar weekday: 1 = Sunday … 7 = Saturday (Gregorian convention).
        let weekday = calendar.component(.weekday, from: date)
        // Map so Monday (2) → 0, …, Sunday (1) → 6.
        return (weekday + 5) % 7
    }
}
