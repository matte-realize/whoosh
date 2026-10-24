import Foundation

/// Applies `RingBufferPolicy` eviction to the `SegmentStore` as segments finish
/// (rear-camera spec task 18; Requirements 5.4, 5.5, 5.10). It is the thin,
/// stateful glue between the pure policy and the store: register the finished
/// segment, compute the effective cap from the storage status, ask the policy
/// which ids to delete, and delete them — never touching the open segment, a
/// pinned segment, or a segment inside a pending post-roll window.
///
/// Pure AVFoundation stays in the recorder; this manager is fully unit-testable
/// with `InMemorySegmentStore` and a scripted free-space value.
///
/// `@MainActor` to match the `SegmentStore`.
@MainActor
final class RingBufferManager {
    private let segmentStore: SegmentStore
    private let tuning: RideCameraTuning
    private let rideId: UUID

    /// The segment currently being written (never evicted). Set by the recorder
    /// path when a new segment opens; cleared when it finishes.
    private var openSegmentId: UUID?
    /// Segment ids inside a pending post-roll window (protected until the pin
    /// finalizes). Maintained by the pinner/coordinator.
    private var pendingWindowIds: Set<UUID> = []

    /// The outcome of applying eviction after a registration.
    struct EvictionOutcome: Equatable, Sendable {
        /// The ids deleted from the store this pass.
        let deletedIds: [UUID]
        /// Whether the ring is still over a bound after evicting everything
        /// eligible (the storage guard decides next, e.g. stop the camera).
        let overBoundUnevictable: Bool
    }

    init(
        segmentStore: SegmentStore,
        rideId: UUID,
        tuning: RideCameraTuning = RideCameraTuning()
    ) {
        self.segmentStore = segmentStore
        self.rideId = rideId
        self.tuning = tuning
    }

    // MARK: - Open-segment / pending-window bookkeeping

    /// Mark the segment currently being written so eviction never removes it.
    func setOpenSegment(_ id: UUID?) {
        openSegmentId = id
    }

    /// Protect the segments inside a pending post-roll window from eviction.
    func setPendingWindow(_ ids: Set<UUID>) {
        pendingWindowIds = ids
    }

    // MARK: - Registration + eviction

    /// Register a finished segment and run an eviction pass. Returns what was
    /// evicted. The finished segment is no longer the open one, so clear
    /// `openSegmentId` first if it matches.
    @discardableResult
    func segmentFinished(_ segment: SegmentInfo) -> EvictionOutcome {
        if openSegmentId == segment.id { openSegmentId = nil }
        segmentStore.register(segment)
        return evict()
    }

    /// Run an eviction pass against the current segment index using the
    /// effective cap derived from the free space the store reports.
    @discardableResult
    func evict() -> EvictionOutcome {
        let free = segmentStore.freeSpace()
        let effectiveBytesCap = StoragePolicy.effectiveRingCap(freeBytes: free, tuning: tuning)
        // At `.warn` the storage policy halves the byte cap; mirror that on the
        // duration cap so the ring also shrinks in time before the stop floor.
        let status = StoragePolicy.status(freeBytes: free, tuning: tuning)
        let effectiveDurationCap: TimeInterval
        switch status {
        case .ok: effectiveDurationCap = tuning.ringMaxDuration
        case .warn: effectiveDurationCap = tuning.ringMaxDuration / 2
        case .stop: effectiveDurationCap = 0
        }

        let segments = segmentStore.segments(rideId: rideId)
        let result = RingBufferPolicy.evict(
            segments: segments,
            openSegmentId: openSegmentId,
            pendingWindowIds: pendingWindowIds,
            maxDuration: effectiveDurationCap,
            maxBytes: effectiveBytesCap
        )
        if !result.deletedIds.isEmpty {
            segmentStore.delete(ids: result.deletedIds)
        }
        return EvictionOutcome(
            deletedIds: result.deletedIds,
            overBoundUnevictable: result.overBoundUnevictable
        )
    }
}
