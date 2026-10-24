import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `RingBufferPolicy` eviction function (rear-camera spec
/// task 3; Requirements 5.4, 5.5, 5.10, 19.2). Written test-first.
///
/// The policy decides which ring-buffer segments to delete so the unpinned
/// footage stays bounded by **both** a maximum duration and a maximum byte size.
/// It is a pure function over `SegmentInfo` values plus the caps; it never
/// touches files. Cases RB-1…8 follow the design's "Ring buffer and
/// RingBufferPolicy" table and the testing-strategy row.
///
/// Invariants asserted throughout:
/// - the open segment, pinned segments, and segments inside a pending post-roll
///   window are never evicted;
/// - eviction is oldest-end-time first (ties by lower index);
/// - a bound that is met exactly does not trigger eviction (strictly greater);
/// - when nothing eligible can bring the ring under bound, nothing is evicted
///   and `overBoundUnevictable` is reported.
struct RingBufferPolicyTests {
    private static let rideID = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
    private static let epoch = Date(timeIntervalSince1970: 1_000_000)

    /// Builds a contiguous run of `count` segments, each `length` seconds long
    /// and `bytes` bytes, starting at `startOffset` seconds after the epoch.
    /// Indices increase with time; ids are deterministic from the index.
    private static func segments(
        count: Int,
        length: TimeInterval = 15,
        bytes: Int64 = 30_000_000,
        startOffset: TimeInterval = 0,
        firstIndex: Int = 0
    ) -> [SegmentInfo] {
        (0..<count).map { i in
            let idx = firstIndex + i
            let start = epoch.addingTimeInterval(startOffset + Double(i) * length)
            return SegmentInfo(
                id: id(idx),
                rideId: rideID,
                index: idx,
                start: start,
                end: start.addingTimeInterval(length),
                bytes: bytes,
                profileName: "Standard",
                hasAudio: false,
                isPinned: false,
                hasGapBefore: false
            )
        }
    }

    /// A stable UUID for a given index so expected-deletion ids are predictable.
    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    // MARK: - RB-1: under both bounds → evict nothing

    @Test func rb1_underBothBoundsEvictsNothing() {
        // 5 × 15 s = 75 s, 5 × 30 MB = 150 MB; both well under 10 min / 1 GB.
        let segs = Self.segments(count: 5)
        let open = segs.last!.id
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 600,
            maxBytes: 1_000_000_000
        )
        #expect(result.deletedIds.isEmpty)
        #expect(result.overBoundUnevictable == false)
    }

    // MARK: - RB-2: exactly at a bound → not evicted (strictly greater)

    @Test func rb2_exactlyAtDurationBoundDoesNotEvict() {
        // 4 × 15 s = 60 s unpinned; the open segment is excluded from the span,
        // so bound the three closed segments (45 s) at exactly 45 s.
        let segs = Self.segments(count: 4)
        let open = segs.last!.id
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 45, // unpinned closed span is exactly 45 s
            maxBytes: 1_000_000_000
        )
        #expect(result.deletedIds.isEmpty)
        #expect(result.overBoundUnevictable == false)
    }

    // MARK: - RB-3: over the duration bound → oldest first until under

    @Test func rb3_overDurationBoundEvictsOldestFirst() {
        // 10 × 15 s closed + 1 open. Cap the duration at 60 s (4 segments).
        let segs = Self.segments(count: 11)
        let open = segs.last!.id // index 10 is the open segment, excluded
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 60, // keep 4 closed segments (60 s); 10 closed exist
            maxBytes: 1_000_000_000
        )
        // 10 closed segments (indices 0…9) span 150 s; keep the newest 60 s
        // (indices 6…9) → delete the oldest 6 (indices 0…5), oldest first.
        #expect(result.deletedIds == (0...5).map(Self.id))
        #expect(result.overBoundUnevictable == false)
    }

    // MARK: - RB-4: over the byte bound → oldest first until under

    @Test func rb4_overByteBoundEvictsOldestFirst() {
        // 10 × 100 MB closed + 1 open; cap bytes at 350 MB (3 closed segments).
        let segs = Self.segments(count: 11, bytes: 100_000_000)
        let open = segs.last!.id
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 10 * 60,
            maxBytes: 350_000_000 // keep 3 closed (300 MB); 10 closed exist
        )
        // Delete the oldest 7 closed segments (indices 0…6).
        #expect(result.deletedIds == (0...6).map(Self.id))
    }

    // MARK: - RB-5: never evict open / pinned / pending-window segments

    @Test func rb5_neverEvictsOpenPinnedOrPendingSegments() {
        var segs = Self.segments(count: 6)
        // Pin the oldest segment (index 0) and put index 1 in a pending window.
        segs[0].isPinned = true
        let open = segs.last!.id // index 5
        let pending: Set<UUID> = [Self.id(1)]
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: pending,
            maxDuration: 1, // force eviction pressure
            maxBytes: 1
        )
        // Pinned (0), pending (1), and open (5) are ineligible; only 2,3,4 can go.
        #expect(!result.deletedIds.contains(Self.id(0)))
        #expect(!result.deletedIds.contains(Self.id(1)))
        #expect(!result.deletedIds.contains(Self.id(5)))
        #expect(result.deletedIds == [2, 3, 4].map(Self.id))
        // Still over bound after evicting everything eligible.
        #expect(result.overBoundUnevictable == true)
    }

    // MARK: - RB-6: eligible set empty but over bound → evict nothing, report

    @Test func rb6_overBoundButNothingEligibleReports() {
        var segs = Self.segments(count: 3)
        segs[0].isPinned = true
        segs[1].isPinned = true
        let open = segs.last!.id // index 2 open; 0,1 pinned
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 1,
            maxBytes: 1
        )
        #expect(result.deletedIds.isEmpty)
        #expect(result.overBoundUnevictable == true)
    }

    // MARK: - RB-7: effective-cap shrink evicts down to the smaller cap

    @Test func rb7_effectiveCapShrinkEvictsDownToIt() {
        // Same 10 closed + open, but the storage guard shrank the byte cap.
        let segs = Self.segments(count: 11, bytes: 50_000_000) // 50 MB each
        let open = segs.last!.id
        let full = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 10 * 60,
            maxBytes: 1_000_000_000 // nothing to evict at the full cap
        )
        #expect(full.deletedIds.isEmpty)

        let shrunk = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 10 * 60,
            maxBytes: 200_000_000 // effective cap: keep 4 closed (200 MB)
        )
        // 10 closed × 50 MB = 500 MB; keep newest 200 MB (indices 6…9) →
        // delete the oldest 6 (indices 0…5).
        #expect(shrunk.deletedIds == (0...5).map(Self.id))
    }

    // MARK: - RB-8: out-of-order registration is sorted by end time first

    @Test func rb8_outOfOrderRegistrationSortsByEndTime() {
        // Build contiguous segments then shuffle their order in the input array.
        let ordered = Self.segments(count: 6)
        let open = ordered.last!.id
        let shuffled: [SegmentInfo] = [
            ordered[3], ordered[0], ordered[5], ordered[2], ordered[4], ordered[1],
        ]
        let result = RingBufferPolicy.evict(
            segments: shuffled,
            openSegmentId: open,
            pendingWindowIds: [],
            maxDuration: 30, // keep 2 closed (30 s); 5 closed exist
            maxBytes: 1_000_000_000
        )
        // 5 closed (indices 0…4) span 75 s; keep newest 30 s (3,4) → delete
        // oldest 3 (0,1,2) in time order regardless of input order.
        #expect(result.deletedIds == [0, 1, 2].map(Self.id))
    }

    // MARK: - extra guards

    @Test func emptyInputIsNoOp() {
        let result = RingBufferPolicy.evict(
            segments: [],
            openSegmentId: nil,
            pendingWindowIds: [],
            maxDuration: 600,
            maxBytes: 1_000_000_000
        )
        #expect(result.deletedIds.isEmpty)
        #expect(result.overBoundUnevictable == false)
    }

    @Test func singleOpenSegmentIsNeverEvicted() {
        let segs = Self.segments(count: 1)
        let result = RingBufferPolicy.evict(
            segments: segs,
            openSegmentId: segs[0].id,
            pendingWindowIds: [],
            maxDuration: 1,
            maxBytes: 1
        )
        #expect(result.deletedIds.isEmpty)
        // The sole segment is the open one; over bound but unevictable.
        #expect(result.overBoundUnevictable == true)
    }

    @Test func tiesBrokenByLowerIndex() {
        // Two closed segments share the same end time; the lower index is older.
        let start = Self.epoch
        let a = SegmentInfo(
            id: Self.id(0), rideId: Self.rideID, index: 0,
            start: start, end: start.addingTimeInterval(15),
            bytes: 30_000_000, profileName: "Standard",
            hasAudio: false, isPinned: false, hasGapBefore: false
        )
        let b = SegmentInfo(
            id: Self.id(1), rideId: Self.rideID, index: 1,
            start: start, end: start.addingTimeInterval(15),
            bytes: 30_000_000, profileName: "Standard",
            hasAudio: false, isPinned: false, hasGapBefore: false
        )
        let openSeg = SegmentInfo(
            id: Self.id(2), rideId: Self.rideID, index: 2,
            start: start.addingTimeInterval(15), end: start.addingTimeInterval(30),
            bytes: 30_000_000, profileName: "Standard",
            hasAudio: false, isPinned: false, hasGapBefore: false
        )
        let result = RingBufferPolicy.evict(
            segments: [b, a, openSeg],
            openSegmentId: openSeg.id,
            pendingWindowIds: [],
            maxDuration: 15, // keep one closed (15 s); two closed exist
            maxBytes: 1_000_000_000
        )
        // Delete exactly the older (lower-index) of the tied pair.
        #expect(result.deletedIds == [Self.id(0)])
    }
}
