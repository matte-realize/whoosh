import Foundation
import Testing
@testable import Whoosh

/// Tests for `DemoDataSeeder` (demo-mode spec, task 7; Requirements 7.1, 7.2,
/// 7.3, 7.5, 7.6). Exercised against `InMemoryRideRepository` so every case is
/// deterministic and leaves no state behind. A `FixedSeederClock` pins "now" so
/// the seeded dates are stable.
@MainActor
struct DemoDataSeederTests {
    private static let now = Date(timeIntervalSince1970: 1_729_784_400) // Sat, Oct 24 2026

    private func makeSeeder(
        repository: InMemoryRideRepository
    ) -> DemoDataSeeder {
        DemoDataSeeder(repository: repository, clock: FixedSeederClock(fixed: Self.now))
    }

    /// A real (non-demo) finished ride, to prove seeding/removal never touches it.
    private static func realRide(_ id: UUID = UUID()) -> Ride {
        Ride(
            id: id,
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-1_800),
            points: [],
            summary: RideSummary(
                distanceMeters: 5_000,
                activeDuration: 1_800,
                averageSpeedMetersPerSecond: 2.78
            ),
            isDemo: false
        )
    }

    // MARK: - Seeding

    @Test func seedInsertsSeveralDemoRides() throws {
        let repo = InMemoryRideRepository()
        let seeder = makeSeeder(repository: repo)

        let inserted = try seeder.seed()

        let all = try repo.allRides()
        #expect(all.count == inserted)
        // The spec asks for ~5–8 realistic rides.
        #expect(inserted >= 5 && inserted <= 8)
        // Every seeded ride is a finished demo ride.
        #expect(all.allSatisfy { $0.isDemo })
        #expect(all.allSatisfy { $0.endedAt != nil })
        // At least one has a real route.
        #expect(all.contains { !$0.points.isEmpty })
    }

    @Test func seededRidesSpanRecentWeeks() throws {
        let repo = InMemoryRideRepository()
        let seeder = makeSeeder(repository: repo)
        _ = try seeder.seed()

        let all = try repo.allRides()
        // All seeded rides are in the past, within the last ~3 weeks.
        let threeWeeksAgo = Self.now.addingTimeInterval(-21 * 86_400)
        #expect(all.allSatisfy { $0.startedAt <= Self.now })
        #expect(all.allSatisfy { $0.startedAt >= threeWeeksAgo })
        // Spread across more than one day (not all stacked on one timestamp).
        let distinctDays = Set(all.map { Int($0.startedAt.timeIntervalSince1970 / 86_400) })
        #expect(distinctDays.count >= 3)
    }

    // MARK: - Removal

    @Test func removeDemoDeletesOnlyDemoRidesLeavingRealRidesUntouched() throws {
        let repo = InMemoryRideRepository()
        let real = Self.realRide()
        try repo.save(real)
        let seeder = makeSeeder(repository: repo)
        _ = try seeder.seed()

        let removed = try seeder.removeDemo()

        let remaining = try repo.allRides()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == real.id)
        #expect(removed >= 5) // all the seeded demo rides were removed
    }

    @Test func removeDemoOnACleanRepositoryRemovesNothing() throws {
        let repo = InMemoryRideRepository()
        let real = Self.realRide()
        try repo.save(real)
        let seeder = makeSeeder(repository: repo)

        let removed = try seeder.removeDemo()

        #expect(removed == 0)
        #expect(try repo.allRides().count == 1)
    }

    // MARK: - Re-seed reporting (O-DM7)

    @Test func existingDemoCountReportsSeededRides() throws {
        let repo = InMemoryRideRepository()
        try repo.save(Self.realRide())
        let seeder = makeSeeder(repository: repo)

        #expect(try seeder.existingDemoCount() == 0)

        let inserted = try seeder.seed()
        // Re-seeding should first report how many demo rides already exist.
        #expect(try seeder.existingDemoCount() == inserted)
    }

    @Test func seedRemovingExistingFirstDoesNotDuplicate() throws {
        let repo = InMemoryRideRepository()
        let seeder = makeSeeder(repository: repo)
        let first = try seeder.seed()

        // Re-seed with remove-first: the demo-ride count returns to a single set.
        let second = try seeder.seed(removingExisting: true)

        #expect(try seeder.existingDemoCount() == second)
        #expect(second == first)
    }
}

/// Fixed `Clock` for deterministic seeding tests.
private struct FixedSeederClock: Clock {
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
