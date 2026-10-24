import Foundation
import Testing
@testable import Whoosh

/// Tests for `HistoryViewModel` (Requirement 7.2–7.4, 7.7, mockup 5 grouping).
///
/// `@MainActor` because the view model inherits the project's default MainActor
/// isolation. Backed by `InMemoryRideRepository` and a fixed `Calendar` so month
/// grouping, counts, totals, ordering, deletion, and the empty/finished-only
/// rules are verified deterministically without a device.
@MainActor
struct HistoryViewModelTests {
    /// A fixed America/New_York, Gregorian calendar for deterministic month
    /// boundaries.
    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    /// Build a `Date` at noon on a specific y/m/d in the fixed calendar.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = fixedCalendar()
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func finishedRide(
        start: Date,
        distanceMeters: Double,
        duration: TimeInterval = 600
    ) -> Ride {
        Ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            points: [],
            summary: RideSummary(
                distanceMeters: distanceMeters,
                activeDuration: duration,
                averageSpeedMetersPerSecond: distanceMeters / duration
            )
        )
    }

    private func makeViewModel(rides: [Ride]) -> (HistoryViewModel, InMemoryRideRepository) {
        let repository = InMemoryRideRepository(rides: rides)
        let vm = HistoryViewModel(repository: repository, calendar: fixedCalendar())
        return (vm, repository)
    }

    // MARK: - Grouping, counts, totals

    @Test func groupsRidesByMonthWithCountsAndTotals() {
        // Three rides in October 2026, one in September 2026.
        let rides = [
            finishedRide(start: date(2026, 10, 22), distanceMeters: 5_000),
            finishedRide(start: date(2026, 10, 20), distanceMeters: 3_000),
            finishedRide(start: date(2026, 10, 18), distanceMeters: 8_000),
            finishedRide(start: date(2026, 9, 27), distanceMeters: 12_000),
        ]
        let (vm, _) = makeViewModel(rides: rides)

        #expect(vm.sections.count == 2)

        let october = vm.sections[0]
        #expect(october.title == "OCTOBER 2026")
        #expect(october.rides.count == 3)
        #expect(october.totalDistanceMeters == 16_000)

        let september = vm.sections[1]
        #expect(september.title == "SEPTEMBER 2026")
        #expect(september.rides.count == 1)
        #expect(september.totalDistanceMeters == 12_000)
    }

    @Test func monthSummaryTextPluralizesAndFormatsMiles() {
        let rides = [
            finishedRide(start: date(2026, 10, 22), distanceMeters: 5_000),
            finishedRide(start: date(2026, 10, 20), distanceMeters: 3_000),
        ]
        let (vm, _) = makeViewModel(rides: rides)
        // 8,000 m ≈ 4.97 mi.
        #expect(vm.sections[0].summaryText == "2 rides · 4.97 mi")

        let single = makeViewModel(rides: [finishedRide(start: date(2026, 9, 1), distanceMeters: 1_609.344)])
        #expect(single.0.sections[0].summaryText == "1 ride · 1.00 mi")
    }

    // MARK: - Ordering

    @Test func sectionsAreNewestMonthFirstAndRidesNewestFirst() {
        let rides = [
            finishedRide(start: date(2026, 9, 10), distanceMeters: 1_000),
            finishedRide(start: date(2026, 10, 5), distanceMeters: 1_000),
            finishedRide(start: date(2026, 10, 25), distanceMeters: 1_000),
        ]
        let (vm, _) = makeViewModel(rides: rides)

        #expect(vm.sections.map(\.title) == ["OCTOBER 2026", "SEPTEMBER 2026"])
        // October rides newest-first: Oct 25 before Oct 5.
        let octStarts = vm.sections[0].rides.map(\.startedAt)
        #expect(octStarts == octStarts.sorted(by: >))
        #expect(vm.sections[0].rides.first?.startedAt == date(2026, 10, 25))
    }

    // MARK: - Deletion

    @Test func deleteRemovesRidePermanently() throws {
        let keep = finishedRide(start: date(2026, 10, 22), distanceMeters: 5_000)
        let remove = finishedRide(start: date(2026, 10, 20), distanceMeters: 3_000)
        let (vm, repository) = makeViewModel(rides: [keep, remove])
        #expect(vm.sections[0].rides.count == 2)

        vm.delete(remove)

        #expect(vm.sections[0].rides.count == 1)
        #expect(vm.sections[0].rides.first?.id == keep.id)
        // Permanent: the repository no longer has it.
        #expect(try repository.ride(id: remove.id) == nil)
    }

    @Test func deletingLastRideInMonthDropsTheSection() {
        let only = finishedRide(start: date(2026, 9, 27), distanceMeters: 1_000)
        let (vm, _) = makeViewModel(rides: [only])
        #expect(vm.sections.count == 1)

        vm.delete(only)
        #expect(vm.sections.isEmpty)
        #expect(vm.isEmpty)
    }

    // MARK: - Empty & finished-only

    @Test func emptyWhenNoRides() {
        let (vm, _) = makeViewModel(rides: [])
        #expect(vm.isEmpty)
        #expect(vm.sections.isEmpty)
    }

    @Test func onlyFinishedRidesAppear() {
        let finished = finishedRide(start: date(2026, 10, 22), distanceMeters: 5_000)
        let inProgress = Ride(
            startedAt: date(2026, 10, 23),
            endedAt: nil,
            points: [],
            summary: .zero
        )
        let (vm, _) = makeViewModel(rides: [finished, inProgress])

        #expect(vm.sections.count == 1)
        #expect(vm.sections[0].rides.count == 1)
        #expect(vm.sections[0].rides.first?.id == finished.id)
    }

    // MARK: - Pure grouping function

    @Test func groupStaticFunctionIsOrderIndependent() {
        let rides = [
            finishedRide(start: date(2026, 10, 1), distanceMeters: 1_000),
            finishedRide(start: date(2026, 10, 31), distanceMeters: 2_000),
            finishedRide(start: date(2026, 8, 15), distanceMeters: 3_000),
        ]
        let sections = HistoryViewModel.group(rides: rides.shuffled(), calendar: fixedCalendar())
        #expect(sections.map(\.title) == ["OCTOBER 2026", "AUGUST 2026"])
        #expect(sections[0].totalDistanceMeters == 3_000)
        #expect(sections[1].totalDistanceMeters == 3_000)
    }
}
