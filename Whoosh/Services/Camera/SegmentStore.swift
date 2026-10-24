import Foundation

/// Abstracts ring-buffer segment storage so the pure policies, the coordinator,
/// and tests reason over an index without touching the file system (rear-camera
/// spec Requirement 5, design "Service protocols: SegmentStore"). `FileSegmentStore`
/// (task 15) is the concrete file-backed type; `InMemorySegmentStore` backs
/// tests and previews.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **On-device only.** Segment files live in app storage, excluded from
///   backups, with a protection class that allows writing after first unlock.
///   Nothing here uploads, links, logs, or transmits a segment.
/// - **Pinning uses hard links.** `link(segmentIds:toClip:)` hard-links segments
///   into a clip (copy fallback in the file impl) and marks them pinned so they
///   no longer count toward the ring bounds; the ring path is then removed.
/// - **Orphans purged on launch.** `purgeOrphans(keepingRides:)` removes segment
///   files with no owning ride (app killed mid-ride, Requirement 17.3).
/// - **Never blocks capture.** Registration/deletion run off the capture queue.
///
/// `AnyObject` because a store is a long-lived reference type owning the index
/// (and, in the file impl, the directory). `freeSpace()` is behind the store so
/// the `StoragePolicy` input is injectable in tests.
@MainActor
protocol SegmentStore: AnyObject {
    /// Register a finished segment in the index.
    func register(_ segment: SegmentInfo)

    /// All segments for a ride, ordered by end time (ties by index).
    func segments(rideId: UUID) -> [SegmentInfo]

    /// Delete the given segments (files and index entries). Safe for unknown ids.
    func delete(ids: [UUID])

    /// Hard-link the given segments into a clip (copy fallback), marking them
    /// pinned so they are no longer counted toward the ring bounds.
    func link(segmentIds: [UUID], toClip clipId: UUID)

    /// Total bytes used by all registered segments.
    func bytesUsed() -> Int64

    /// Remove any segment files/entries not owned by one of `keepingRides`
    /// (launch-time orphan purge).
    func purgeOrphans(keepingRides: Set<UUID>)

    /// Free space usable for important data (the `StoragePolicy` input).
    func freeSpace() -> Int64
}
