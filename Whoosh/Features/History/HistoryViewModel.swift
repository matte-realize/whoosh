import Foundation
import Observation

/// View model for the History screen (Requirement 7, mockup 5).
///
/// Loads finished rides (`endedAt != nil`) most-recent-first from the
/// `RideRepository`, groups them into month sections (newest month first) with a
/// per-month ride count and total distance for the header, and exposes a
/// `delete(_:)` intent that permanently removes a ride and reloads.
///
/// Grouping and totals are computed with an injected `Clock`-free `Calendar`
/// (defaulting to `.current`) so the logic is deterministic and unit-testable
/// without a device. UI-framework-free (no SwiftUI import), per the layering
/// table; it depends only on model types and the `RideRepository` protocol.
@Observable
@MainActor
final class HistoryViewModel {
    /// A month's worth of rides for one section of the list.
    struct MonthSection: Identifiable, Equatable {
        /// Stable id: the first day of the month (used for ordering too).
        let id: Date
        /// Section header title, e.g. "OCTOBER 2026" (uppercased).
        let title: String
        /// Rides in this month, most-recent-first.
        let rides: [Ride]
        /// Total distance across the month's rides, in meters.
        let totalDistanceMeters: Double

        /// e.g. "4 rides · 18.7 mi" for the header's right side.
        var summaryText: String {
            let countText = rides.count == 1 ? "1 ride" : "\(rides.count) rides"
            return "\(countText) · \(Formatters.miles(fromMeters: totalDistanceMeters))"
        }
    }

    @ObservationIgnored private let repository: RideRepository
    @ObservationIgnored private let calendar: Calendar

    /// Finished rides grouped into month sections, newest month first.
    private(set) var sections: [MonthSection] = []

    init(repository: RideRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
        load()
    }

    /// `true` when there are no finished rides — drives the friendly empty state.
    var isEmpty: Bool { sections.isEmpty }

    // MARK: - Intents

    /// (Re)load finished rides from the repository and rebuild the month
    /// sections. Corrupt records are skipped by the repository (Requirement 7.7).
    func load() {
        let finished = ((try? repository.allRides()) ?? []).filter { $0.endedAt != nil }
        sections = Self.group(rides: finished, calendar: calendar)
    }

    /// Permanently delete a ride and reload (Requirement 7.4). A missing id is a
    /// safe no-op in the repository.
    func delete(_ ride: Ride) {
        try? repository.delete(id: ride.id)
        load()
    }

    // MARK: - Grouping (pure)

    /// Group finished rides into month sections, newest month first, rides
    /// within a month most-recent-first. Exposed `static` so it is trivially
    /// unit-testable with a fixed `Calendar`.
    static func group(rides: [Ride], calendar: Calendar) -> [MonthSection] {
        // Sort newest-first so both sections and in-section rides are ordered.
        let sorted = rides.sorted { $0.startedAt > $1.startedAt }

        var order: [Date] = []
        var byMonth: [Date: [Ride]] = [:]
        for ride in sorted {
            let monthStart = startOfMonth(for: ride.startedAt, calendar: calendar)
            if byMonth[monthStart] == nil {
                byMonth[monthStart] = []
                order.append(monthStart)
            }
            byMonth[monthStart]?.append(ride)
        }

        return order.map { monthStart in
            let monthRides = byMonth[monthStart] ?? []
            let total = monthRides.reduce(0) { $0 + $1.summary.distanceMeters }
            return MonthSection(
                id: monthStart,
                title: monthTitle(for: monthStart, calendar: calendar),
                rides: monthRides,
                totalDistanceMeters: total
            )
        }
    }

    /// The first instant of the month containing `date`.
    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// e.g. "OCTOBER 2026" — fixed en_US + the calendar's time zone so the
    /// header matches the mockup and stays deterministic in tests.
    private static func monthTitle(for monthStart: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthStart).uppercased()
    }
}
