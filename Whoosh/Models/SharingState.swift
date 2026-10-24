import Foundation

/// A ride's derived public-sharing state, shown with icon + text on the summary
/// and in history (Requirement 12.15). Pure value type (Models layer).
///
/// Derived from a ride's `sharePublicly` flag and its `syncStatus`:
/// - `.private`: not shared (or the ride never left the device).
/// - `.shared`: shared and the remote row is confirmed (`.synced`).
/// - `.sharingPending`: the desired sharing state has not yet been mirrored
///   remotely (upload/unshare still queued).
nonisolated enum SharingState: Equatable, Sendable {
    case `private`
    case shared
    case sharingPending

    /// Derives the sharing state for a ride.
    static func forRide(sharePublicly: Bool, syncStatus: SyncStatus) -> SharingState {
        guard sharePublicly else { return .private }
        switch syncStatus {
        case .synced:
            return .shared
        case .localOnly, .pending, .failed:
            // The user intends to share, but the remote row isn't confirmed yet.
            return .sharingPending
        }
    }

    var title: String {
        switch self {
        case .private: return "Private"
        case .shared: return "Shared"
        case .sharingPending: return "Sharing pending"
        }
    }
}
