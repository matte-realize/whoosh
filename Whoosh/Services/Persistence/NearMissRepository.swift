import Foundation

/// Abstraction over near-miss event storage so the recorder, summary/history,
/// sync, and tests are swappable and fakeable (rear-camera spec Requirement 15,
/// task 28). The SwiftData implementation (`SwiftDataNearMissRepository`) is the
/// default; `InMemoryNearMissRepository` backs unit tests and previews.
///
/// Near-miss events live in a **separate** entity from `RideRecord` so the
/// shipped ride model never migrates (the same D-CAM8 pattern as clips/crash
/// alerts); the cascade on ride deletion runs through `deleteAll(rideId:)`.
///
/// ## Contract
/// - An event references the nearest **accepted** route point (or no coordinate
///   when it fell inside the privacy-trim zone). It carries an optional
///   **local-only** clip id that is never uploaded — `NearMissUploadMapper`
///   drops it. Role C receives events only, never video.
/// - **Real deletion.** `delete`, `deleteAll(rideId:)`, and `deleteAll()` remove
///   records; deletion is real, never a soft flag.
///
/// All operations `throws` so storage failures surface to the caller (matching
/// `RideRepository`/`ClipRepository`). Implementations run on the main actor in
/// this project (default isolation; SwiftData's `ModelContext` is main-actor).
protocol NearMissRepository {
    /// Persist an event, inserting a new record or updating the existing one
    /// with the same `id`.
    func save(_ event: NearMissEvent) throws

    /// All events for a ride, oldest-first (by `occurredAt`, ascending) so they
    /// line up with the recorded route order.
    func events(rideId: UUID) throws -> [NearMissEvent]

    /// Permanently remove every event for a ride (ride-deletion cascade).
    func deleteAll(rideId: UUID) throws

    /// Permanently remove every stored event (Settings "Delete all rides").
    func deleteAll() throws
}
