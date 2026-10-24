import Foundation

/// In-memory `NearMissRepository` used by unit tests and SwiftUI previews.
///
/// Keeps events in a dictionary keyed by `id`, so `save` upserts and the deletes
/// are harmless no-ops for missing ids. `events(rideId:)` returns the ride's
/// events oldest-first by `occurredAt` so they line up with the route order. No
/// persistence across process launches — that is the SwiftData implementation's
/// job.
///
/// Lives under `Services/Persistence/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
final class InMemoryNearMissRepository: NearMissRepository {
    private var eventsByID: [UUID: NearMissEvent] = [:]

    init(events: [NearMissEvent] = []) {
        for event in events { eventsByID[event.id] = event }
    }

    func save(_ event: NearMissEvent) throws {
        eventsByID[event.id] = event
    }

    func events(rideId: UUID) throws -> [NearMissEvent] {
        eventsByID.values
            .filter { $0.rideId == rideId }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func deleteAll(rideId: UUID) throws {
        for (id, event) in eventsByID where event.rideId == rideId {
            eventsByID[id] = nil
        }
    }

    func deleteAll() throws {
        eventsByID.removeAll()
    }
}
