import Foundation
import Testing
@testable import Whoosh

/// Tests for `RingBufferManager` (rear-camera spec task 18; Requirements 5.4,
/// 5.5, 5.10). The pure eviction math is covered by `RingBufferPolicyTests`;
/// here we verify the manager's glue: register-then-evict, open-segment and
/// pending-window protection, pinned exclusion, and the effective-cap shrink the
/// storage status drives. Uses `InMemorySegmentStore` with a scripted free-space
/// value — no AVFoundation.
///
/// `@MainActor` to match the manager/store.
@MainActor
struct RingBufferManagerTests {
    private static let rideID = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
    private static let t0 = Date(timeIntervalSince1970: 3_000_000)
    private static let segmentLength: TimeInterval = 15

    private func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private func segment(
        index: Int,
        bytes: Int64 = 30_000_000,
        isPinned: Bool = false
    ) -> SegmentInfo {
        let start = Self.t0.addingTimeInterval(Double(index) * Self.segmentLength)
        return SegmentInfo(
            id: id(index),
            rideId: Self.rideID,
            index: index,
            start: start,
            end: start.addingTimeInterval(Self.segmentLength),
            bytes: bytes,
            profileName: "Standard",
            hasAudio: false,
            isPinned: isPinned,
            hasGapBefore: false
        )
    }

    private func makeManager(
        segments: [SegmentInfo] = [],
        freeSpaceBytes: Int64 = 8_000_000_000,
        tuning: RideCameraTuning = RideCameraTuning()
    ) -> (manager: RingBufferManager, store: InMemorySegmentStore) {
        let store = InMemorySegmentStore(segments: segments, freeSpaceBytes: freeSpaceBytes)
        let manager = RingBufferManager(segmentStore: store, rideId: Self.rideID, tuning: tuning)
        return (manager, store)
    }

    // MARK: - RM-1: within the duration cap, nothing is evicted

    @Test func withinDurationCapKeepsEverything() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 10 * 60 // 40 segments * 15 s = 600 s == cap
        tuning.ringMaxBytes = 100_000_000_000
        let (manager, store) = makeManager(tuning: tuning)
        for i in 0..<10 { manager.segmentFinished(segment(index: i)) }
        // 10 * 15 s = 150 s < 600 s cap, well under bytes ⇒ no eviction.
        #expect(store.segments(rideId: Self.rideID).count == 10)
    }

    // MARK: - RM-2: over the duration cap evicts oldest first

    @Test func overDurationCapEvictsOldestFirst() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 45 // only 3 segments (3 * 15) fit
        tuning.ringMaxBytes = 100_000_000_000
        let (manager, store) = makeManager(tuning: tuning)
        for i in 0..<5 { manager.segmentFinished(segment(index: i)) }
        // 5 segments = 75 s > 45 s; evict oldest until ≤ 45 s ⇒ keep indices 2,3,4.
        #expect(store.segments(rideId: Self.rideID).map(\.index) == [2, 3, 4])
    }

    // MARK: - RM-3: over the byte cap evicts oldest first

    @Test func overByteCapEvictsOldestFirst() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 100 * 60
        tuning.ringMaxBytes = 90 // only 3 segments of 30 bytes fit
        let (manager, store) = makeManager(tuning: tuning)
        for i in 0..<5 { manager.segmentFinished(segment(index: i, bytes: 30)) }
        #expect(store.segments(rideId: Self.rideID).map(\.index) == [2, 3, 4])
    }

    // MARK: - RM-4: the open segment is never evicted

    @Test func openSegmentIsNeverEvicted() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 15 // only 1 segment fits by duration
        tuning.ringMaxBytes = 100_000_000_000
        let (manager, store) = makeManager(tuning: tuning)
        for i in 0..<3 { manager.segmentFinished(segment(index: i)) }
        // Open the next segment (index 3), then evict: index 3 must survive even
        // though the ring is over the 15 s cap.
        manager.setOpenSegment(id(3))
        store.register(segment(index: 3))
        manager.evict()
        #expect(store.segments(rideId: Self.rideID).contains { $0.index == 3 })
    }

    // MARK: - RM-5: pinned segments are excluded from the ring bound

    @Test func pinnedSegmentsAreNotEvictedAndDoNotCountTowardBound() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 30 // 2 unpinned segments fit
        tuning.ringMaxBytes = 100_000_000_000
        // index 0 is pinned (out of the ring); indices 1..4 are unpinned.
        let segs = [segment(index: 0, isPinned: true)] + (1..<5).map { segment(index: $0) }
        let (manager, store) = makeManager(segments: segs, tuning: tuning)
        manager.evict()
        let remaining = store.segments(rideId: Self.rideID)
        // The pinned segment stays; unpinned trimmed to the last two (3,4).
        #expect(remaining.contains { $0.index == 0 && $0.isPinned })
        #expect(remaining.filter { !$0.isPinned }.map(\.index) == [3, 4])
    }

    // MARK: - RM-6: a pending post-roll window is protected

    @Test func pendingWindowSegmentsAreProtected() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 15 // only 1 segment fits
        tuning.ringMaxBytes = 100_000_000_000
        let (manager, store) = makeManager(tuning: tuning)
        for i in 0..<4 { manager.segmentFinished(segment(index: i)) }
        // Protect the oldest two as a pending post-roll window.
        manager.setPendingWindow([id(0), id(1)])
        manager.evict()
        let remaining = store.segments(rideId: Self.rideID).map(\.index)
        #expect(remaining.contains(0))
        #expect(remaining.contains(1))
    }

    // MARK: - RM-7: low storage (warn) shrinks the effective cap

    @Test func warnStorageShrinksEffectiveCap() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 10 * 60 // 600 s nominal
        tuning.ringMaxBytes = 100_000_000_000
        // Free space in the warn band (< 1 GB warn, ≥ 500 MB stop).
        let (manager, store) = makeManager(freeSpaceBytes: 800_000_000, tuning: tuning)
        // 30 segments = 450 s. Nominal cap 600 s keeps all; warn halves it to
        // 300 s ⇒ keep only the last 20.
        for i in 0..<30 { manager.segmentFinished(segment(index: i)) }
        #expect(store.segments(rideId: Self.rideID).count == 20)
    }

    // MARK: - RM-8: overBoundUnevictable reported when only protected footage remains

    @Test func overBoundUnevictableWhenOnlyOpenSegmentExceedsCap() {
        var tuning = RideCameraTuning()
        tuning.ringMaxDuration = 5 // one 15 s segment already exceeds the cap
        tuning.ringMaxBytes = 100_000_000_000
        let (manager, store) = makeManager(tuning: tuning)
        // Register one segment and mark it open (cannot be evicted).
        store.register(segment(index: 0))
        manager.setOpenSegment(id(0))
        let outcome = manager.evict()
        #expect(outcome.deletedIds.isEmpty)
        #expect(outcome.overBoundUnevictable)
        #expect(store.segments(rideId: Self.rideID).count == 1)
    }
}
