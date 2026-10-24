import Foundation
import Testing
@testable import Whoosh

/// Tests for `HomeViewModel` (Requirements 13.2–13.6, 2.2–2.4, 1.2).
///
/// `@MainActor` because the view model inherits the project's default MainActor
/// isolation. Dependencies are injected as fakes — `InMemoryRideRepository`, a
/// deterministic `TestClock`, a Monday-first `Calendar`, and a
/// `FakeLocationTracker` — so weekly aggregation, recent-ride selection, and
/// authorization mapping are all verified without a device.
@MainActor
struct HomeViewModelTests {
    // A fixed reference instant: Thursday, Oct 24 2024 (America/New_York). The
    // Monday-first week containing it runs Mon Oct 21 … Sun Oct 27.
    private let now = Date(timeIntervalSince1970: 1_729_784_400)

    private func mondayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func makeViewModel(
        rides: [Ride] = [],
        status: LocationAuthorizationStatus = .authorizedWhenInUse
    ) -> (HomeViewModel, FakeLocationTracker) {
        let repository = InMemoryRideRepository(rides: rides)
        let tracker = FakeLocationTracker(authorizationStatus: status)
        let vm = HomeViewModel(
            repository: repository,
            clock: TestClock(now: now),
            calendar: mondayCalendar(),
            tracker: tracker
        )
        return (vm, tracker)
    }

    /// A finished ride at `start` with the given summary numbers.
    private func finishedRide(
        start: Date,
        distance: Double,
        duration: TimeInterval,
        avgSpeed: Double = 5
    ) -> Ride {
        Ride(
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            points: [],
            summary: RideSummary(
                distanceMeters: distance,
                activeDuration: duration,
                averageSpeedMetersPerSecond: avgSpeed
            )
        )
    }

    // MARK: - Weekly numbers

    @Test func weeklyStatsAggregatesFinishedRidesInCurrentWeek() {
        let calendar = mondayCalendar()
        // Reference `now` is Thursday, Oct 24 2024. This Monday-first week runs
        // Mon Oct 21 … Sun Oct 27. Place rides on Monday, Wednesday, Thursday.
        let monday = calendar.date(byAdding: .day, value: -3, to: now) ?? now // Oct 21
        let wednesday = calendar.date(byAdding: .day, value: -1, to: now) ?? now // Oct 23
        let thursday = now // Oct 24

        let rides = [
            finishedRide(start: monday, distance: 5_000, duration: 900),
            finishedRide(start: wednesday, distance: 8_000, duration: 1_200),
            finishedRide(start: thursday, distance: 2_000, duration: 400),
        ]
        let (vm, _) = makeViewModel(rides: rides)

        let stats = vm.weeklyStats
        #expect(stats.rideCount == 3)
        #expect(stats.totalDistanceMeters == 15_000)
        #expect(stats.totalActiveDuration == 2_500)
        #expect(stats.distancePerWeekday.count == 7)
        // Monday bucket (index 0), Wednesday (index 2), Thursday (index 3).
        #expect(stats.distancePerWeekday[0] == 5_000)
        #expect(stats.distancePerWeekday[2] == 8_000)
        #expect(stats.distancePerWeekday[3] == 2_000)
    }

    @Test func weeklyStatsIgnoresRidesOutsideCurrentWeek() {
        let calendar = mondayCalendar()
        // -10d is Mon Oct 14 (previous week); -1d is Wed Oct 23 (this week).
        let lastWeek = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let thisWeek = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        let rides = [
            finishedRide(start: lastWeek, distance: 9_999, duration: 5_000),
            finishedRide(start: thisWeek, distance: 3_000, duration: 600),
        ]
        let (vm, _) = makeViewModel(rides: rides)

        let stats = vm.weeklyStats
        #expect(stats.rideCount == 1)
        #expect(stats.totalDistanceMeters == 3_000)
    }

    // MARK: - Recent rides: limit, order, finished-only

    @Test func recentRidesAreLimitedToThreeMostRecentFirst() {
        // Five finished rides on consecutive days.
        let rides = (0..<5).map { i -> Ride in
            let start = now.addingTimeInterval(Double(-i) * 86_400)
            return finishedRide(start: start, distance: Double(1_000 * (i + 1)), duration: 600)
        }
        let (vm, _) = makeViewModel(rides: rides)

        #expect(vm.recentRides.count == HomeViewModel.recentRidesLimit)
        // Most-recent-first: the first element is the latest start date.
        let starts = vm.recentRides.map(\.startedAt)
        #expect(starts == starts.sorted(by: >))
        #expect(vm.recentRides.first?.startedAt == now)
    }

    @Test func onlyFinishedRidesAppear() {
        let finished = finishedRide(start: now, distance: 1_000, duration: 300)
        // An in-progress ride (endedAt == nil) must be filtered out.
        let inProgress = Ride(
            startedAt: now.addingTimeInterval(60),
            endedAt: nil,
            points: [],
            summary: .zero
        )
        let (vm, _) = makeViewModel(rides: [finished, inProgress])

        #expect(vm.rides.count == 1)
        #expect(vm.rides.first?.id == finished.id)
        #expect(vm.recentRides.allSatisfy { $0.endedAt != nil })
        // The in-progress ride also must not pollute weekly counts.
        #expect(vm.weeklyStats.rideCount == 1)
    }

    // MARK: - Authorization → Home state mapping

    @Test func authorizedStatusMapsToReadyDashboard() {
        let (vm, _) = makeViewModel(status: .authorizedWhenInUse)
        #expect(vm.state == .ready)
        #expect(vm.showsDashboard)
    }

    @Test func notDeterminedMapsToNeedsPermissionButStillShowsDashboard() {
        let (vm, _) = makeViewModel(status: .notDetermined)
        #expect(vm.state == .needsPermission)
        #expect(vm.showsDashboard)
    }

    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted])
    func deniedAndRestrictedMapToDeniedStateHidingDashboard(
        status: LocationAuthorizationStatus
    ) {
        let (vm, _) = makeViewModel(status: status)
        #expect(vm.state == .denied)
        #expect(vm.showsDashboard == false)
    }

    @Test func authorizationChangeUpdatesStateLive() {
        let (vm, tracker) = makeViewModel(status: .notDetermined)
        #expect(vm.state == .needsPermission)

        tracker.changeAuthorization(.denied)
        #expect(vm.state == .denied)
        #expect(vm.showsDashboard == false)

        tracker.changeAuthorization(.authorizedWhenInUse)
        #expect(vm.state == .ready)
        #expect(vm.showsDashboard)
    }

    @Test func requestLocationOnlyPromptsWhenNotDetermined() {
        let (vm, tracker) = makeViewModel(status: .notDetermined)
        vm.requestLocationIfNeeded()
        #expect(tracker.requestAuthorizationCount == 1)

        // Already authorized → no further prompt.
        let (vm2, tracker2) = makeViewModel(status: .authorizedWhenInUse)
        vm2.requestLocationIfNeeded()
        #expect(tracker2.requestAuthorizationCount == 0)
    }

    // MARK: - Empty state

    @Test func emptyStateWhenNoRides() {
        let (vm, _) = makeViewModel(rides: [])
        #expect(vm.hasNoRides)
        #expect(vm.recentRides.isEmpty)
        #expect(vm.weeklyStats == .empty)
    }

    @Test func reloadPicksUpNewlySavedRides() throws {
        let repository = InMemoryRideRepository()
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        let vm = HomeViewModel(
            repository: repository,
            clock: TestClock(now: now),
            calendar: mondayCalendar(),
            tracker: tracker
        )
        #expect(vm.hasNoRides)

        try repository.save(finishedRide(start: now, distance: 1_000, duration: 300))
        vm.load()
        #expect(vm.rides.count == 1)
        #expect(vm.hasNoRides == false)
    }
}
