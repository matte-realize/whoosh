import Foundation

/// A terminal (non-retryable) outcome thrown by `RideSyncService.upload` so the
/// `SyncCoordinator` records the right local `SyncStatus` instead of blindly
/// marking every failure `.pending` (Requirements 12.18, 12.20, 12.22).
///
/// - `.localOnly`: the ride legitimately has nothing to upload (fewer than 2
///   points after trimming, or a demo ride). Keep it `.localOnly`; never retry.
/// - `.failed`: the ride was permanently rejected — a client-side limit
///   pre-check failed, or the server returned a `23514` check violation. Mark
///   it `.failed`; never retry in a loop.
///
/// Any *other* thrown error (offline, 5xx, auth) is retryable and the
/// coordinator marks the ride `.pending`.
nonisolated enum RideSyncTerminalOutcome: Error, Equatable, Sendable {
    case localOnly
    case failed
}
