import Foundation

/// The "unhappy path" states the demo tools can preview on stage without
/// changing any real permission or persistent state (Requirement 8). The
/// `StatePreviewHost` renders the matching real view state; dismissing clears it
/// with no side effect.
enum DemoStatePreview: Equatable, Sendable, CaseIterable {
    /// The location-denied Home state (MVP Req 2.2).
    case locationDenied
    /// The amber signal-lost ride banner (MVP Req 5.3).
    case signalLost
    /// The calm storage-unavailable notice (MVP Req 11.4).
    case storageUnavailable
    /// The real crash countdown/status screens driven by the drill path
    /// (Crash Req 8, 11.6); Call 911 hidden.
    case crashCountdown
}
