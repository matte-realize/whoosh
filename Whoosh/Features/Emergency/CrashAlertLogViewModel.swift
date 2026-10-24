import Foundation
import Observation

/// View model for `CrashAlertLogView`, the Settings → "Crash alerts" → log
/// screen (spec Requirement 11.5, 11.9, task 22).
///
/// Lists `CrashAlertRecord`s **most-recent-first** (the repository already
/// orders by `detectedAt` descending), lets the rider delete one record or all
/// records (real deletion, Requirement 11.5), and purges records older than the
/// local retention window on load (Requirement 11.9). It reads the record's
/// overall state and per-recipient attempts so the view can render icon + text
/// statuses.
///
/// UI-framework-free (no SwiftUI import), per the layering table; it depends on
/// the `CrashAlertRepository` protocol, the injected `Clock`, and model types.
@Observable
@MainActor
final class CrashAlertLogViewModel {
    @ObservationIgnored private let repository: CrashAlertRepository
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let retention: TimeInterval

    /// The records to show, most-recent-first.
    private(set) var records: [CrashAlertRecord] = []
    /// A user-facing message when a delete/load fails; never raw error text.
    var errorMessage: String?

    init(
        repository: CrashAlertRepository,
        clock: Clock,
        retention: TimeInterval = CrashResponseTuning().localRecordRetention
    ) {
        self.repository = repository
        self.clock = clock
        self.retention = retention
        load()
    }

    /// `true` when there are no records to show (drives the empty state).
    var isEmpty: Bool { records.isEmpty }

    /// Purge expired records, then (re)load the list most-recent-first. Called on
    /// init and whenever the log reappears.
    func load() {
        errorMessage = nil
        purgeExpired()
        do {
            records = try repository.all()
        } catch {
            records = []
            errorMessage = "Couldn't load your crash alert log. Please try again."
        }
    }

    /// Permanently delete one record (Requirement 11.5).
    func delete(id: UUID) {
        errorMessage = nil
        do {
            try repository.delete(id: id)
        } catch {
            errorMessage = "Couldn't delete that record. Please try again."
        }
        load()
    }

    /// Permanently delete every record (Requirement 11.5).
    func deleteAll() {
        errorMessage = nil
        do {
            try repository.deleteAll()
        } catch {
            errorMessage = "Couldn't delete the log. Please try again."
        }
        load()
    }

    // MARK: - Retention

    /// Remove records whose event is older than the retention window
    /// (Requirement 11.9). Failures are non-fatal — a purge error should not
    /// stop the log from showing.
    private func purgeExpired() {
        let cutoff = clock.now().addingTimeInterval(-retention)
        try? repository.purge(olderThan: cutoff)
    }
}
