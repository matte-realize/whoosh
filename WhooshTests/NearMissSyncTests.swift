import Foundation
import Testing
@testable import Whoosh

/// Tests for the near-miss upload path (rear-camera spec Requirement 15, task
/// 28): events are upserted **after** their ride, demo events are never
/// uploaded, and events inside the privacy-trim zone are dropped.
///
/// `@MainActor` because the coordinator, fake service, and repositories are all
/// main-actor isolated.
@MainActor
struct NearMissSyncTests {
    private static let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180

    /// A long-enough ride so the privacy trim keeps an interior. ~100 m spacing.
    private static func ride(
        _ id: UUID = UUID(),
        isDemo: Bool = false,
        sharePublicly: Bool = false,
        status: SyncStatus = .localOnly
    ) -> Ride {
        let start = Date(timeIntervalSince1970: 1_000)
        let degPerStep = 100 / metersPerDegreeLon
        let points = (0..<21).map { i in
            RoutePoint(
                latitude: 0,
                longitude: Double(i) * degPerStep,
                timestamp: start.addingTimeInterval(Double(i)),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
        return Ride(
            id: id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            points: points,
            summary: RideSummary(distanceMeters: 2_000, activeDuration: 1_200, averageSpeedMetersPerSecond: 1.67),
            sharePublicly: sharePublicly,
            syncStatus: status,
            isDemo: isDemo
        )
    }

    /// The coordinate of the Nth point of `ride` (so an event can sit on an
    /// accepted route point).
    private static func point(_ ride: Ride, _ index: Int) -> RoutePoint { ride.points[index] }

    private static func nearMiss(
        rideId: UUID,
        at point: RoutePoint,
        occurredAt: Date,
        isDemo: Bool = false,
        kind: String = "vehicle"
    ) -> NearMissEvent {
        NearMissEvent(
            id: UUID(),
            rideId: rideId,
            occurredAt: occurredAt,
            latitude: point.latitude,
            longitude: point.longitude,
            kind: kind,
            confidence: 0.8,
            positionHint: "left",
            source: .detected,
            isDemo: isDemo,
            localClipId: nil
        )
    }

    private func makeCoordinator(
        service: FakeRideSyncService,
        repo: InMemoryRideRepository,
        nearMisses: InMemoryNearMissRepository
    ) -> SyncCoordinator {
        SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore(),
            nearMissEvents: { (try? nearMisses.events(rideId: $0)) ?? [] }
        )
    }

    // The ride row is uploaded before its near misses, so the FK resolves.
    @Test func rideUploadsBeforeItsNearMisses() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride()
        try repo.save(ride)
        // A near miss on a middle (kept) point.
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride)

        // The ride was uploaded, then exactly one near-miss batch followed it.
        #expect(service.uploadedIDs == [ride.id])
        #expect(service.uploadedNearMissBatches.count == 1)
        #expect(service.uploadedNearMissBatches.first?.count == 1)
    }

    // A demo ride is never uploaded, and neither are its near-miss events.
    @Test func demoRideAndItsNearMissesNeverUpload() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride(isDemo: true)
        try repo.save(ride)
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride)

        #expect(service.uploadedIDs.isEmpty)
        #expect(service.uploadedNearMissBatches.isEmpty)
    }

    // A demo near miss on a real ride is still never uploaded (it is filtered
    // out of the batch), even though the ride itself uploads.
    @Test func demoEventOnRealRideIsFilteredOut() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride()
        try repo.save(ride)
        // One real event (kept) + one demo event (must not upload).
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 11), occurredAt: ride.startedAt.addingTimeInterval(11), isDemo: true))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride)

        #expect(service.uploadedIDs == [ride.id])
        let batch = try #require(service.uploadedNearMissBatches.first)
        #expect(batch.count == 1) // only the real event
    }

    // An event near the start (inside the 160 m privacy-trim zone) is dropped;
    // an event in the kept interior is uploaded.
    @Test func trimZoneEventIsDropped() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride()
        try repo.save(ride)
        // Point 0 is at the very start → trimmed away (within 160 m). Point 10 is
        // deep in the interior → kept.
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 0), occurredAt: ride.startedAt))
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride)

        let batch = try #require(service.uploadedNearMissBatches.first)
        #expect(batch.count == 1) // start-zone event dropped, interior kept
    }

    // The stamped global sharing flag flows onto each near-miss payload.
    @Test func nearMissPayloadCarriesRideSharingFlag() async throws {
        let service = FakeRideSyncService()
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride()
        try repo.save(ride)
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride, shareNewRidesPublicly: true)

        let batch = try #require(service.uploadedNearMissBatches.first)
        #expect(batch.first?.sharePublicly == true)
    }

    // A disabled service uploads nothing — ride or near misses.
    @Test func disabledServiceUploadsNoNearMisses() async throws {
        let service = FakeRideSyncService(isEnabled: false)
        let repo = InMemoryRideRepository()
        let nmRepo = InMemoryNearMissRepository()
        let ride = Self.ride()
        try repo.save(ride)
        try nmRepo.save(Self.nearMiss(rideId: ride.id, at: Self.point(ride, 10), occurredAt: ride.startedAt.addingTimeInterval(10)))
        let coordinator = makeCoordinator(service: service, repo: repo, nearMisses: nmRepo)

        await coordinator.rideDidFinish(ride)
        await coordinator.retryPending()

        #expect(service.uploadedIDs.isEmpty)
        #expect(service.uploadedNearMissBatches.isEmpty)
    }
}

/// Tests for the pure `NearMissTrimFilter` (privacy steering "Privacy zones").
struct NearMissTrimFilterTests {
    private static let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180

    private static func points() -> [RoutePoint] {
        let start = Date(timeIntervalSince1970: 1_000)
        let degPerStep = 100 / metersPerDegreeLon
        return (0..<21).map { i in
            RoutePoint(
                latitude: 0,
                longitude: Double(i) * degPerStep,
                timestamp: start.addingTimeInterval(Double(i)),
                speedMetersPerSecond: 5,
                horizontalAccuracyMeters: 5
            )
        }
    }

    private static func event(at point: RoutePoint) -> NearMissEvent {
        NearMissEvent(
            id: UUID(),
            rideId: UUID(),
            occurredAt: Date(timeIntervalSince1970: 1_000),
            latitude: point.latitude,
            longitude: point.longitude,
            kind: "vehicle",
            confidence: 0.8,
            positionHint: nil,
            localClipId: nil
        )
    }

    @Test func dropsEndpointZoneKeepsInterior() {
        let pts = Self.points()
        let events = [
            Self.event(at: pts[0]),   // start zone → dropped
            Self.event(at: pts[10]),  // interior → kept
            Self.event(at: pts[20]),  // end zone → dropped
        ]
        let kept = NearMissTrimFilter.uploadable(events: events, points: pts, meters: 160)
        #expect(kept.count == 1)
        #expect(kept.first?.latitude == pts[10].latitude)
    }

    @Test func dropsEventWithNoCoordinate() {
        let pts = Self.points()
        let noCoord = NearMissEvent(
            id: UUID(), rideId: UUID(), occurredAt: Date(),
            latitude: nil, longitude: nil, kind: "vehicle",
            confidence: 0.8, positionHint: nil, localClipId: nil
        )
        let kept = NearMissTrimFilter.uploadable(events: [noCoord], points: pts, meters: 160)
        #expect(kept.isEmpty)
    }
}
