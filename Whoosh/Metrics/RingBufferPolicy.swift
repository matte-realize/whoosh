import Foundation

/// Pure ring-buffer eviction policy for rear-camera recording (rear-camera spec
/// task 3; Requirements 5.4, 5.5, 5.10). Decides which rolling segments to
/// delete so the **unpinned** footage stays bounded by both a maximum duration
/// and a maximum byte size.
///
/// Framework-free (Metrics layer: Models + Foundation only). It reasons over
/// `SegmentInfo` values and the caps; it never touches the file system — the
/// `SegmentStore` deletes the returned ids. Time is wall-clock `Date`/
/// `TimeInterval`, never `CMTime`.
///
/// Contract (design "Ring buffer and RingBufferPolicy"):
/// - **Eligibility.** The currently open (being-written) segment, any pinned
///   segment, and any segment inside a pending post-roll window are never
///   evicted. Only the remaining *closed, unpinned, not-pending* segments are
///   candidates.
/// - **Bound.** The bound is measured over the closed-unpinned span and bytes
///   (the open segment is still being written and is excluded from the span).
///   Eviction runs while the span is strictly greater than `maxDuration` **or**
///   the bytes are strictly greater than `maxBytes`; a bound met exactly does
///   not trigger eviction.
/// - **Order.** Oldest end time first; ties broken by the lower `index`.
/// - **Effective-cap shrink.** When the storage guard reduces a cap, the same
///   function evicts down to the smaller cap.
/// - **Unevictable.** If the eligible set is exhausted and the ring is still
///   over a bound, nothing more is deleted and `overBoundUnevictable` is `true`
///   so the storage guard can decide (e.g. stop the camera).
/// - **Out-of-order input.** Segments are sorted by end time (then index)
///   before deciding, so registration order does not matter.
enum RingBufferPolicy {
    /// The outcome of an eviction pass.
    struct Result: Equatable, Sendable {
        /// Ids to delete, in eviction order (oldest first). Empty if nothing is
        /// evicted.
        let deletedIds: [UUID]
        /// `true` when the ring is still over a bound after evicting every
        /// eligible segment (the open/pinned/pending segments alone exceed the
        /// cap). The storage guard decides what to do next.
        let overBoundUnevictable: Bool

        init(deletedIds: [UUID], overBoundUnevictable: Bool) {
            self.deletedIds = deletedIds
            self.overBoundUnevictable = overBoundUnevictable
        }
    }

    /// Returns the segments to delete so the closed-unpinned ring falls within
    /// both caps. See the type doc for the full contract. Never mutates input.
    ///
    /// - Parameters:
    ///   - segments: the current segment index (any order).
    ///   - openSegmentId: the segment currently being written, or `nil` if none
    ///     is open; it is never evicted and never counted toward the span.
    ///   - pendingWindowIds: segment ids inside a pending post-roll window; they
    ///     are protected from eviction until the pin finalizes.
    ///   - maxDuration: the ring duration cap in seconds (effective cap after any
    ///     storage-guard shrink).
    ///   - maxBytes: the ring byte cap (effective cap after any shrink).
    static func evict(
        segments: [SegmentInfo],
        openSegmentId: UUID?,
        pendingWindowIds: Set<UUID>,
        maxDuration: TimeInterval,
        maxBytes: Int64
    ) -> Result {
        // Candidates: closed, unpinned, not in a pending window. Sorted oldest
        // end time first, ties by lower index — this is also the eviction order.
        let candidates = segments
            .filter { seg in
                seg.id != openSegmentId
                    && !seg.isPinned
                    && !pendingWindowIds.contains(seg.id)
            }
            .sorted { lhs, rhs in
                if lhs.end != rhs.end { return lhs.end < rhs.end }
                return lhs.index < rhs.index
            }

        // The span/bytes we bound are those of the closed-unpinned set: the open
        // segment is still being written and is excluded; pinned segments have
        // left the ring (hard-linked into a clip) and do not count.
        var remaining = candidates
        var totalBytes = candidates.reduce(Int64(0)) { $0 + $1.bytes }

        var deleted: [UUID] = []
        // Evict oldest-first while strictly over either bound and a candidate is
        // left to evict.
        while !remaining.isEmpty,
              isOverBound(remaining, totalBytes: totalBytes, maxDuration: maxDuration, maxBytes: maxBytes) {
            let victim = remaining.removeFirst()
            totalBytes -= victim.bytes
            deleted.append(victim.id)
        }

        // Unevictable: there is no eligible candidate left, yet the footage that
        // still physically occupies the ring (the open segment plus any pending
        // post-roll segments — pinned segments have left the ring) is over a
        // bound. The storage guard decides what to do next (e.g. stop the
        // camera). When eligible candidates remain, the loop stopped because the
        // ring is within bound, so this is `false`.
        let deletedSet = Set(deleted)
        let protectedOccupying = segments.filter { seg in
            !seg.isPinned && !deletedSet.contains(seg.id)
        }
        let protectedBytes = protectedOccupying.reduce(Int64(0)) { $0 + $1.bytes }
        let overBoundUnevictable = remaining.isEmpty
            && isOverBound(
                protectedOccupying,
                totalBytes: protectedBytes,
                maxDuration: maxDuration,
                maxBytes: maxBytes
            )
        return Result(deletedIds: deleted, overBoundUnevictable: overBoundUnevictable)
    }

    // MARK: - Private

    /// Whether the given closed-unpinned set is strictly over either bound.
    /// A bound met exactly does not count (strictly greater triggers).
    private static func isOverBound(
        _ segments: [SegmentInfo],
        totalBytes: Int64,
        maxDuration: TimeInterval,
        maxBytes: Int64
    ) -> Bool {
        guard !segments.isEmpty else { return false }
        return span(of: segments) > maxDuration || totalBytes > maxBytes
    }

    /// The summed duration of the closed-unpinned set, in seconds. Segments are
    /// contiguous under normal operation; summing per-segment durations is
    /// robust to gaps (an interruption) where a start-to-end span would wrongly
    /// include the gap.
    private static func span(of segments: [SegmentInfo]) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}
