import Foundation

/// In-memory `RideRepository` used by unit tests and SwiftUI previews.
///
/// Keeps rides in a dictionary keyed by `id`, so `save` upserts and `delete`
/// of a missing id is a harmless no-op. `allRides()` sorts most-recent-first by
/// `startedAt`. No persistence across process launches — that is the SwiftData
/// implementation's job.
///
/// Lives under `Services/Persistence/` (not the test target) so previews and
/// the composition root can inject it; tests reach it via `@testable import`.
final class InMemoryRideRepository: RideRepository {
    private var ridesByID: [UUID: Ride] = [:]

    init(rides: [Ride] = []) {
        for ride in rides {
            ridesByID[ride.id] = ride
        }
    }

    func save(_ ride: Ride) throws {
        ridesByID[ride.id] = ride
    }

    func allRides() throws -> [Ride] {
        ridesByID.values.sorted { $0.startedAt > $1.startedAt }
    }

    func ride(id: UUID) throws -> Ride? {
        ridesByID[id]
    }

    func delete(id: UUID) throws {
        ridesByID.removeValue(forKey: id)
    }

    func deleteAll() throws {
        ridesByID.removeAll()
    }
}
