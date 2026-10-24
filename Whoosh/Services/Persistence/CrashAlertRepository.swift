import Foundation

/// Abstraction over crash-alert record storage (spec Requirement 11.1).
///
/// A `CrashAlertRecord` is persisted per crash event with its event fields,
/// location snapshots, rendered text, and per-recipient attempts. Records are
/// kept until the rider deletes them or the local retention (default 90 days)
/// elapses; deletion is real (Requirement 11.5, 11.9). The record **never**
/// stores a full phone number — only the masked last-2-digits per attempt
/// (Requirement 11.3).
///
/// `SwiftDataCrashAlertRepository` is the shipping implementation;
/// `InMemoryCrashAlertRepository` backs unit tests and previews. Operations
/// `throws` so storage failures surface rather than being swallowed.
///
/// Implementations run on the main actor in this project (default MainActor
/// isolation; SwiftData's `ModelContext` is main-actor here).
@MainActor
protocol CrashAlertRepository {
    /// Persist a record, inserting a new row or updating the existing one with
    /// the same id (= `crashEventId`).
    func save(_ record: CrashAlertRecord) throws

    /// All stored records, most-recent-first (by the event's `detectedAt`,
    /// descending). Corrupt/undecodable records are skipped rather than throwing
    /// (same policy as the ride repository).
    func all() throws -> [CrashAlertRecord]

    /// The record with the given id, or `nil` if none exists.
    func record(id: UUID) throws -> CrashAlertRecord?

    /// Permanently remove the record with the given id. Deleting a missing id
    /// is a safe no-op (Requirement 11.5).
    func delete(id: UUID) throws

    /// Permanently remove every stored record (real deletion, Requirement 11.5).
    func deleteAll() throws

    /// Permanently remove records whose event `detectedAt` is older than
    /// `date`. Used to enforce the local retention window (Requirement 11.9).
    func purge(olderThan date: Date) throws

    /// The single active (non-resting) event, if any, for relaunch recovery
    /// (Requirement 13.5). Returns `nil` when every stored record is in a
    /// resting state. At most one event is active at a time (Requirement 6.9).
    func activeEvent() throws -> CrashAlertRecord?
}
