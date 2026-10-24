import Foundation

/// The lifecycle state of a pinned clip (rear-camera spec Requirement 6.2,
/// design "Pinning and ClipWindowPolicy"). A clip is written `pending` and flips
/// to `saved` once its post-roll completes, or to `endedEarly` if the ride ends
/// before the post-roll is captured.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum ClipState: String, Equatable, Codable, Sendable, CaseIterable {
    /// Post-roll not yet captured; covering segments are protected from eviction.
    case pending
    /// Post-roll complete; the clip is final and playable.
    case saved
    /// The ride ended before the post-roll completed; finalized with what exists.
    case endedEarly = "ended_early"
}
