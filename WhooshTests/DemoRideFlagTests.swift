import Foundation
import SwiftData
import Testing
@testable import Whoosh

/// Tests for the `isDemo` flag on `Ride`/`RideRecord` and its sync/stats
/// exclusion (demo-mode spec, task 3; Requirements 5.5, 7.4, 9.3; O-DM2).
///
/// The flag defaults to `false` so every existing caller and stored ride is
/// unaffected (lightweight migration, exactly like `syncStatus`). Demo rides are
/// never uploaded by the `SyncCoordinator` and are excluded from the Home
/// This-Week stats (O-DM2 = exclude).
@MainActor
struct DemoRideFlagTests {
    private static let t0 = Date(timeIntervalSince1970: 1_000)

    private static func ride(
        _ id: UUID = UUID(),
        startedAt: Date = t0,
        isDemo: Bool = false,
        status: SyncStatus = .localOnly
    ) -> Ride {
        Ride(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            points: [],
            summary: RideSummary(
                distanceMeters: 1_234,
                activeDuration: 600,
                averageSpeedMetersPerSecond: 2.05
            ),
            syncStatus: status,
            isDemo: isDemo
        )
    }

    // MARK: - Default source-compatibility

    @Test func rideDefaultsToNotDemo() {
        let ride = Ride(startedAt: Self.t0)
        #expect(ride.isDemo == false)
    }

    // MARK: - Persistence round-trip + migration

    @Test func swiftDataRoundTripsIsDemoTrue() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RideRecord.self, configurations: config)
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let demo = Self.ride(isDemo: true)
        try repo.save(demo)
        #expect(try repo.ride(id: demo.id)?.isDemo == true)
    }

    @Test func swiftDataRoundTripsIsDemoFalse() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RideRecord.self, configurations: config)
        let repo = SwiftDataRideRepository(context: ModelContext(container))
        let real = Self.ride(isDemo: false)
        try repo.save(real)
        #expect(try repo.ride(id: real.id)?.isDemo == false)
    }

    /// A record inserted *without* setting `isDemo` (modelling a row written by
    /// a build before the flag shipped) reads back as `false` — the defaulted
    /// stored attribute makes this a lightweight migration, like `syncStatus`.
    @Test func legacyRecordWithoutFlagReadsBackAsNotDemo() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RideRecord.self, configurations: config)
        let context = ModelContext(container)
        let repo = SwiftDataRideRepository(context: context)

        // Insert a record the way old code would have, omitting the new field so
        // its stored default applies.
        let legacy = RideRecord(
            id: UUID(),
            startedAt: Self.t0,
            endedAt: Self.t0.addingTimeInterval(600),
            distanceMeters: 0,
            activeDuration: 0,
            averageSpeed: 0,
            encodedPoints: try JSONEncoder().encode([RoutePoint]())
        )
        context.insert(legacy)
        try context.save()

        #expect(try repo.ride(id: legacy.id)?.isDemo == false)
    }

    @Test func inMemoryRepositoryRoundTripsIsDemo() throws {
        let repo = InMemoryRideRepository()
        let demo = Self.ride(isDemo: true)
        try repo.save(demo)
        #expect(try repo.ride(id: demo.id)?.isDemo == true)
    }

    // MARK: - Sync exclusion (Req 9.3)

    @Test func syncCoordinatorNeverUploadsADemoRideOnFinish() async throws {
        let service = FakeRideSyncService() // enabled
        let repo = InMemoryRideRepository()
        let coordinator = SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        let demo = Self.ride(isDemo: true)
        try repo.save(demo)

        await coordinator.rideDidFinish(demo)

        #expect(service.uploadedIDs.isEmpty)
        // The demo ride's status is left untouched (never advanced to pending).
        #expect(try repo.ride(id: demo.id)?.syncStatus == .localOnly)
    }

    @Test func retryPendingSkipsDemoRidesEvenIfMarkedPending() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let coordinator = SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        // A demo ride that somehow carries `.pending` must still never upload.
        let demo = Self.ride(isDemo: true, status: .pending)
        try repo.save(demo)

        await coordinator.retryPending()

        #expect(service.uploadedIDs.isEmpty)
    }

    @Test func realRideStillUploadsAlongsideADemoRide() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let coordinator = SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        let real = Self.ride(isDemo: false)
        let demo = Self.ride(isDemo: true)
        try repo.save(real)
        try repo.save(demo)

        await coordinator.rideDidFinish(real)
        await coordinator.rideDidFinish(demo)

        #expect(service.uploadedIDs == [real.id])
    }

    // MARK: - Weekly stats exclusion (O-DM2 = exclude)

    @Test func homeWeeklyStatsExcludeDemoRides() {
        let now = Date(timeIntervalSince1970: 1_729_784_400) // Sat, Oct 24 2026
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday

        let real = Self.ride(startedAt: now.addingTimeInterval(-86_400), isDemo: false)
        let demo = Self.ride(startedAt: now.addingTimeInterval(-2 * 86_400), isDemo: true)

        let repo = InMemoryRideRepository(rides: [real, demo])
        let tracker = FakeLocationTracker(authorizationStatus: .authorizedWhenInUse)
        let vm = HomeViewModel(
            repository: repo,
            clock: FixedTestClock(fixed: now),
            calendar: calendar,
            tracker: tracker
        )

        // Only the real ride counts toward the week's totals.
        #expect(vm.weeklyStats.rideCount == 1)
        #expect(vm.weeklyStats.totalDistanceMeters == real.summary.distanceMeters)
    }

    /// The pure calculator itself stays demo-unaware: given the same rides it
    /// counts them all. Exclusion is the caller's job (O-DM2 recommendation).
    @Test func weeklyStatsCalculatorRemainsDemoUnaware() {
        let now = Date(timeIntervalSince1970: 1_729_784_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let real = Self.ride(startedAt: now.addingTimeInterval(-86_400), isDemo: false)
        let demo = Self.ride(startedAt: now.addingTimeInterval(-2 * 86_400), isDemo: true)

        let stats = WeeklyStatsCalculator.compute(
            rides: [real, demo],
            now: now,
            calendar: calendar
        )
        #expect(stats.rideCount == 2)
    }
}

/// A trivial fixed `Clock` for deterministic stats tests (mirrors the private
/// `FixedClock` used in previews; declared here so the test target can use it).
private struct FixedTestClock: Clock {
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
