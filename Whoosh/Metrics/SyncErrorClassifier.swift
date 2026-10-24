import Foundation

/// How the sync layer should react to a failed request (Requirement 12.22).
///
/// Pure value type so the classification is unit-tested without the Supabase
/// SDK. The `SupabaseRideSyncService` maps each case to a `SyncStatus` /
/// retry decision:
/// - `.permanent` → `.failed` (do not retry in a loop).
/// - `.authRetryable` → refresh the anonymous session and retry on the next trigger.
/// - `.retryable` → `.pending` (retry on app foreground).
nonisolated enum SyncErrorClass: Equatable, Sendable {
    /// A `23514` check violation — the row breaks a contract limit. Permanent.
    case permanent
    /// A `42501` permission-denied or an auth/session error. Retry after a
    /// session refresh.
    case authRetryable
    /// Offline, timeout, or a transient 5xx. Retry later.
    case retryable
}

/// Pure classifier for a PostgREST error code (Requirement 12.22).
///
/// Kept framework-free (Metrics layer) so the "`23514` is permanent, `42501` is
/// retry-after-refresh" rule is unit-tested without a live server.
nonisolated enum SyncErrorClassifier {
    /// Classify by the PostgREST error `code` string (e.g. `"23514"`,
    /// `"42501"`). `nil` (no code — typically a transport/offline error) is
    /// treated as retryable.
    static func classify(postgrestCode code: String?) -> SyncErrorClass {
        switch code {
        case "23514":
            return .permanent
        case "42501":
            return .authRetryable
        default:
            return .retryable
        }
    }
}
