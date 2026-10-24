import Foundation

/// The computed result of pinning a window (rear-camera spec Requirement 6,
/// design "Pinning and ClipWindowPolicy"). The keep-set is snapped outward to
/// segment boundaries while the in/out offsets stay exact for playback/export.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct PinWindow: Equatable, Codable, Sendable {
    /// Ids of the segments to keep (link into the clip folder).
    let segmentIds: [UUID]
    /// Exact playback in-point offset in seconds from the first kept segment.
    let inOffset: TimeInterval
    /// Exact playback out-point offset in seconds from the first kept segment.
    let outOffset: TimeInterval
    /// If the post-roll is still in the future, the instant it completes; the
    /// clip stays `pending` and covering segments are protected until then.
    let pendingUntil: Date?
    /// Whether a recording gap falls inside the window (interruption).
    let hasGap: Bool
    /// Whether the window was clamped because the ride started less than `pre`
    /// seconds before the event.
    let truncatedAtRideStart: Bool

    init(
        segmentIds: [UUID],
        inOffset: TimeInterval,
        outOffset: TimeInterval,
        pendingUntil: Date?,
        hasGap: Bool,
        truncatedAtRideStart: Bool
    ) {
        self.segmentIds = segmentIds
        self.inOffset = inOffset
        self.outOffset = outOffset
        self.pendingUntil = pendingUntil
        self.hasGap = hasGap
        self.truncatedAtRideStart = truncatedAtRideStart
    }

    /// Whether the window produced any footage to keep.
    var isEmpty: Bool { segmentIds.isEmpty }
}
