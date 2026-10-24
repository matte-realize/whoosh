import Foundation

/// Metadata for one recorded ring-buffer segment (rear-camera spec
/// Requirement 5, design "Entities"). The in-memory segment index is rebuilt
/// from the files on launch; this value type is what `RingBufferPolicy` and
/// `ClipWindowPolicy` reason over. Time is wall-clock `Date`, never `CMTime`.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`, `Identifiable`.
struct SegmentInfo: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    let rideId: UUID
    /// Monotonic index within the ride (ties broken by this when end times equal).
    let index: Int
    /// Wall-clock start of the segment.
    let start: Date
    /// Wall-clock end of the segment.
    let end: Date
    /// Bytes on disk.
    let bytes: Int64
    /// The capture profile name in effect for the segment.
    let profileName: String
    /// Whether the segment contains an audio track (audio is a Stretch; off now).
    let hasAudio: Bool
    /// Whether the segment is pinned into a clip (no longer counted toward the ring).
    var isPinned: Bool
    /// Whether there is a recording gap immediately before this segment
    /// (first frame after an interruption/restart/format change).
    let hasGapBefore: Bool

    init(
        id: UUID,
        rideId: UUID,
        index: Int,
        start: Date,
        end: Date,
        bytes: Int64,
        profileName: String,
        hasAudio: Bool,
        isPinned: Bool,
        hasGapBefore: Bool
    ) {
        self.id = id
        self.rideId = rideId
        self.index = index
        self.start = start
        self.end = end
        self.bytes = bytes
        self.profileName = profileName
        self.hasAudio = hasAudio
        self.isPinned = isPinned
        self.hasGapBefore = hasGapBefore
    }

    /// Segment duration in seconds.
    var duration: TimeInterval { end.timeIntervalSince(start) }
}
