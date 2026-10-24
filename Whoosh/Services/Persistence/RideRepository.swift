import Foundation

/// Abstraction over ride storage so the engine is swappable and fakeable in
/// tests (Requirement 7.5). The SwiftData implementation is the recommended
/// default; `InMemoryRideRepository` backs unit tests and SwiftUI previews.
///
/// All operations `throws` so storage failures can be surfaced to the caller
/// rather than being silently swallowed. The repository is the only layer that
/// knows how rides are persisted; view models depend on this protocol alone.
///
/// Implementations run on the main actor in this project (default MainActor
/// isolation; SwiftData's `ModelContext` is main-actor here), which keeps them
/// directly usable from `@MainActor` view models.
protocol RideRepository {
    /// Persist a ride, inserting a new record or updating the existing one with
    /// the same `id`.
    func save(_ ride: Ride) throws

    /// All stored rides, most-recent-first (by `startedAt`, descending).
    /// Corrupt/undecodable records are skipped rather than throwing
    /// (Requirement 7.7).
    func allRides() throws -> [Ride]

    /// The ride with the given `id`, or `nil` if none exists.
    func ride(id: UUID) throws -> Ride?

    /// Permanently remove the ride with the given `id`. Deleting a missing id
    /// is a safe no-op (Requirement 7.4).
    func delete(id: UUID) throws

    /// Permanently remove every stored ride (real deletion, not a soft flag).
    /// Invoked from the Settings "Delete all rides" action (Requirement 7.8).
    func deleteAll() throws
}
