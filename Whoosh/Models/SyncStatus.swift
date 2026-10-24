import Foundation

/// The cloud-sync state of a ride (Requirements 6.6 / 7.2 / 12).
///
/// Until opt-in Supabase sync ships (tasks 26–28) every ride is `.localOnly`,
/// which the UI surfaces as "On device". The three cases mirror the sync-status
/// indicator shown in the ride summary and history rows (icon + text, never
/// color alone). Pure value type, Foundation-only, per the layering table.
nonisolated enum SyncStatus: String, Equatable, Codable, Sendable, CaseIterable {
    /// Stored only on this device; not uploaded. Shown as "On device".
    case localOnly
    /// Queued for upload / awaiting a successful sync. Shown as "Pending".
    case pending
    /// Successfully uploaded to the Whoosh map. Shown as "Synced".
    case synced
    /// Permanently rejected by the backend (e.g. a `23514` check violation) or
    /// a client-side pre-check limit failure (Requirement 12.20/12.22). Not
    /// retried in a loop. Shown as "Failed".
    case failed

    /// The user-facing label (icon + text pairing lives in the design system).
    var title: String {
        switch self {
        case .localOnly: return "On device"
        case .pending: return "Pending"
        case .synced: return "Synced"
        case .failed: return "Failed"
        }
    }
}
