import Foundation
import Testing
@testable import Whoosh

/// A fake `RideSyncTransport` so `SupabaseRideSyncService` tests never touch the
/// network (task 28e). Records calls and can be scripted to throw a specific
/// PostgREST code or a code-less (offline) error.
actor FakeRideSyncTransport: RideSyncTransport {
    private(set) var ensureSessionCount = 0
    private(set) var upsertedRows: [RideUploadRow] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var sharingUpdates: [(id: UUID, shared: Bool)] = []
    private(set) var nearMissBatches: [[NearMissUploadMapper.Payload]] = []

    /// Codes to throw on the next upsert calls (consumed front to back). `nil`
    /// entry = a code-less transport/offline error.
    var upsertErrorCodes: [String?] = []

    func setUpsertErrorCodes(_ codes: [String?]) { upsertErrorCodes = codes }

    func ensureSession() async throws {
        ensureSessionCount += 1
    }

    func upsert(_ row: RideUploadRow) async throws {
        if !upsertErrorCodes.isEmpty {
            let code = upsertErrorCodes.removeFirst()
            throw SyncTransportError(code: code, message: "scripted")
        }
        upsertedRows.append(row)
    }

    func delete(id: UUID) async throws {
        deletedIDs.append(id)
    }

    func updateSharing(id: UUID, shared: Bool) async throws {
        sharingUpdates.append((id, shared))
    }

    func upsertNearMisses(_ rows: [NearMissUploadMapper.Payload]) async throws {
        nearMissBatches.append(rows)
    }
}

struct SupabaseRideSyncServiceTests {
    private static let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180

    private static func ride(
        _ id: UUID = UUID(),
        points count: Int = 50,
        sharePublicly: Bool = false
    ) -> Ride {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let degPerStep = 50 / metersPerDegreeLon
        let points = (0..<count).map { i in
            RoutePoint(
                latitude: 42,
                longitude: -71 + Double(i) * degPerStep,
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
            sharePublicly: sharePublicly
        )
    }

    private func makeService(
        transport: FakeRideSyncTransport,
        enabled: Bool = true
    ) -> SupabaseRideSyncService {
        SupabaseRideSyncService(
            transport: transport,
            appVersion: "1.0.0",
            isEnabled: { enabled }
        )
    }

    // MARK: upload success → full column upsert

    @Test func uploadUpsertsEveryColumn() async throws {
        let transport = FakeRideSyncTransport()
        let service = makeService(transport: transport)

        try await service.upload(Self.ride(sharePublicly: true))

        let rows = await transport.upsertedRows
        let row = try #require(rows.first)
        // Every owned column is present (full-column upsert).
        #expect(row.sharePublicly == true)
        #expect(row.appVersion == "1.0.0")
        #expect(row.distanceM == 2_000)
        #expect(row.activeDurationS == 1_200)
        #expect(row.route.type == "LineString")
        #expect((row.route.coordinates?.count ?? 0) >= 2)
    }

    // MARK: 23514 permanent vs 42501 retryable

    @Test func checkViolationIsPermanentFailure() async throws {
        let transport = FakeRideSyncTransport()
        await transport.setUpsertErrorCodes(["23514"])
        let service = makeService(transport: transport)

        await #expect(throws: RideSyncTerminalOutcome.failed) {
            try await service.upload(Self.ride())
        }
        // No retry loop: upsert was attempted exactly once (then threw).
        let rows = await transport.upsertedRows
        #expect(rows.isEmpty)
    }

    @Test func permissionDeniedRefreshesSessionAndRetries() async throws {
        let transport = FakeRideSyncTransport()
        // First upsert → 42501; after a session refresh the retry succeeds.
        await transport.setUpsertErrorCodes(["42501"])
        let service = makeService(transport: transport)

        try await service.upload(Self.ride())

        let rows = await transport.upsertedRows
        #expect(rows.count == 1)                       // retry succeeded
        let sessions = await transport.ensureSessionCount
        #expect(sessions >= 2)                          // initial + refresh
    }

    @Test func offlineErrorIsRetryableAndRethrown() async throws {
        let transport = FakeRideSyncTransport()
        await transport.setUpsertErrorCodes([nil])      // code-less = offline
        let service = makeService(transport: transport)

        await #expect(throws: SyncTransportError.self) {
            try await service.upload(Self.ride())
        }
    }

    // MARK: < 2 points → localOnly terminal outcome

    @Test func tinyRideThrowsLocalOnlyTerminalOutcome() async throws {
        let transport = FakeRideSyncTransport()
        let service = makeService(transport: transport)

        // The caller (SyncCoordinator) privacy-trims before upload, per the
        // RideSyncService contract; a route left with < 2 points stays local.
        await #expect(throws: RideSyncTerminalOutcome.localOnly) {
            try await service.upload(Self.ride(points: 1))
        }
        let rows = await transport.upsertedRows
        #expect(rows.isEmpty)
    }

    // MARK: setSharing

    @Test func setSharingUpdatesRemoteFlag() async throws {
        let transport = FakeRideSyncTransport()
        let service = makeService(transport: transport)
        let id = UUID()

        try await service.setSharing(id: id, shared: false)

        let updates = await transport.sharingUpdates
        #expect(updates.count == 1)
        #expect(updates.first?.id == id)
        #expect(updates.first?.shared == false)
    }
}

/// Coordinator-level sharing tests (task 28e): stamping at finalize is not
/// retroactive, the unshare path calls `setSharing(false)`.
@MainActor
struct SyncCoordinatorSharingTests {
    private static let metersPerDegreeLon = RideMetrics.earthRadiusMeters * .pi / 180

    private static func ride(
        _ id: UUID = UUID(),
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
            syncStatus: status
        )
    }

    private func makeCoordinator(_ service: FakeRideSyncService) -> (SyncCoordinator, InMemoryRideRepository) {
        let repo = InMemoryRideRepository()
        let coordinator = SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        return (coordinator, repo)
    }

    @Test func finishStampsSharingFromGlobalFlagNotRetroactively() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo) = makeCoordinator(service)
        let ride = Self.ride()
        try repo.save(ride)

        // Sharing was ON when this ride finished → stamped true and uploaded.
        await coordinator.rideDidFinish(ride, shareNewRidesPublicly: true)

        let uploaded = try #require(service.uploadedRides.first)
        #expect(uploaded.sharePublicly == true)
        #expect(try repo.ride(id: ride.id)?.sharePublicly == true)
    }

    @Test func finishWithSharingOffStampsFalse() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo) = makeCoordinator(service)
        let ride = Self.ride(sharePublicly: true) // stale true
        try repo.save(ride)

        await coordinator.rideDidFinish(ride, shareNewRidesPublicly: false)

        let uploaded = try #require(service.uploadedRides.first)
        #expect(uploaded.sharePublicly == false)
    }

    @Test func unshareRidesCallsSetSharingFalse() async throws {
        let service = FakeRideSyncService()
        let (coordinator, repo) = makeCoordinator(service)
        let ride = Self.ride(sharePublicly: true, status: .synced)
        try repo.save(ride)

        await coordinator.unshareRides([ride])

        #expect(service.setSharingCalls == [.init(id: ride.id, shared: false)])
        #expect(try repo.ride(id: ride.id)?.sharePublicly == false)
    }

    @Test func permanentFailureMarksRideFailed() async throws {
        // A service that throws the permanent terminal outcome.
        let service = TerminalOutcomeSyncService(outcome: .failed)
        let repo = InMemoryRideRepository()
        let coordinator = SyncCoordinator(
            service: service,
            repository: repo,
            pendingDeletes: InMemoryPendingRemoteDeleteStore()
        )
        let ride = Self.ride()
        try repo.save(ride)

        await coordinator.rideDidFinish(ride)

        #expect(try repo.ride(id: ride.id)?.syncStatus == .failed)
    }

    @Test func disabledServiceMakesNoSharingCalls() async throws {
        let service = FakeRideSyncService(isEnabled: false)
        let (coordinator, repo) = makeCoordinator(service)
        let ride = Self.ride(sharePublicly: true, status: .synced)
        try repo.save(ride)

        await coordinator.rideDidFinish(ride, shareNewRidesPublicly: true)
        await coordinator.unshareRides([ride])

        #expect(service.uploadedIDs.isEmpty)
        #expect(service.setSharingCalls.isEmpty)
    }
}

/// A `RideSyncService` that always throws a given terminal outcome, to test the
/// coordinator's terminal-status mapping.
@MainActor
final class TerminalOutcomeSyncService: RideSyncService {
    let outcome: RideSyncTerminalOutcome
    var isEnabled: Bool { true }

    init(outcome: RideSyncTerminalOutcome) { self.outcome = outcome }

    func upload(_ ride: Ride) async throws { throw outcome }
    func deleteRemote(id: UUID) async throws {}
    func setSharing(id: UUID, shared: Bool) async throws {}
    func uploadNearMisses(_ payloads: [NearMissUploadMapper.Payload]) async throws {}
}
