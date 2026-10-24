import Foundation

/// The cloud-sync state of a ride (Requirements 6.6 / 7.2 / 12).
///
/// Until opt-in Supabase sync ships (tasks 26–28) every ride is `.localOnly`,
/// which the UI surfaces as "On device". The three cases mirror the sync-status
/// indicator shown in the ride summary and history rows (icon + text, never
/// color alone). Pure value type, Foundation-only, per the layering table.
enum SyncStatus: String, Equatable, Codable, Sendable, CaseIterable {
    /// Stored only on this device; not uploaded. Shown as "On device".
    case localOnly
    /// Queued for upload / awaiting a successful sync. Shown as "Pending".
    case pending
    /// Successfully uploaded to the Whoosh map. Shown as "Synced".
    case synced

    /// The user-facing label (icon + text pairing lives in the design system).
    var title: String {
        switch self {
        case .localOnly: return "On device"
        case .pending: return "Pending"
        case .synced: return "Synced"
        }
    }
}
