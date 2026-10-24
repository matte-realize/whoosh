import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure clip-pinning policies (rear-camera spec task 4;
/// Requirements 6.2, 6.4, 6.5, 6.6, 6.9, 11.7). Written test-first.
///
/// `ClipWindowPolicy.window(...)` turns a `PinRequest` (plus the pre/post from
/// `RideCameraTuning`, the available segment index, `now`, and the ride start)
/// into a `PinWindow`: the keep-set snapped outward to segment boundaries, exact
/// in/out offsets from the first kept segment, a `pendingUntil` when the
/// post-roll is still in the future, a `hasGap` flag when an interruption falls
/// inside the window, a `truncatedAtRideStart` flag when the ride started less
/// than `pre` before the event, and an empty window when nothing is available.
///
/// `ClipCoalescing.coalesce(...)` merges a new window into an overlapping or
/// near-adjacent existing clip (within the coalesce gap), up to the maximum clip
/// duration, keeping every contributing reason; beyond the cap it starts a new
/// clip (a shared boundary segment is linked into both). Manual saves are
/// allowed until the pinned cap; auto-pins are refused at the cap.
///
/// Cases CW-1…10 follow the design's "Pinning and ClipWindowPolicy" table.
struct ClipWindowPolicyTests {
    private static let rideID = UUID(uuidString: "00000000-0000-0000-0000-00000000CAFE")!
    /// Ride starts at epoch; segments are 15 s and contiguous from there.
    private static let rideStart = Date(timeIntervalSince1970: 2_000_000)
    private static let segmentLength: TimeInterval = 15

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    /// Contiguous 15 s segments indexed 0…count-1 starting at `rideStart`.
    /// Segment `i` covers [rideStart + 15i, rideStart + 15(i+1)].
    private static func segments(count: Int, gapBeforeIndex: Int? = nil) -> [SegmentInfo] {
        (0..<count).map { i in
            let start = rideStart.addingTimeInterval(Double(i) * segmentLength)
            return SegmentInfo(
                id: id(i),
                rideId: rideID,
                index: i,
                start: start,
                end: start.addingTimeInterval(segmentLength),
                bytes: 30_000_000,
                profileName: "Standard",
                hasAudio: false,
                isPinned: false,
                hasGapBefore: gapBeforeIndex == i
            )
        }
    }

    /// Time at `seconds` after the ride start.
    private static func t(_ seconds: TimeInterval) -> Date {
        rideStart.addingTimeInterval(seconds)
    }

    // MARK: - CW-1: normal window snaps outward to segment boundaries

    @Test func cw1_normalWindowSnapsOutward() {
        // 20 segments (300 s). Event at 150 s, detection pre 15 / post 10.
        // Window = [135 s, 160 s]. Segment 9 = [135,150], 10 = [150,165].
        let segs = Self.segments(count: 20)
        let request = PinRequest(reason: .detection, eventTime: Self.t(150), eventRef: "nm-1")
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 15,
            post: 10,
            segments: segs,
            now: Self.t(300), // post-roll already in the past
            rideStart: Self.rideStart
        )
        // Keep segments 9 and 10 (135…165 covers [135,160]).
        #expect(window.segmentIds == [Self.id(9), Self.id(10)])
        // First kept segment starts at 135 s; in-point 135 s ⇒ offset 0.
        #expect(window.inOffset == 0)
        // Out-point 160 s ⇒ 25 s from the first kept segment start.
        #expect(window.outOffset == 25)
        #expect(window.pendingUntil == nil)
        #expect(window.hasGap == false)
        #expect(window.truncatedAtRideStart == false)
    }

    // MARK: - CW-2: window interior to one segment keeps exact offsets

    @Test func cw2_interiorOffsetsAreExact() {
        // Event at 40 s, pre 5 / post 5 ⇒ [35,45], both inside segment 2
        // ([30,45]). Keep only segment 2; in 35-30=5, out 45-30=15.
        let segs = Self.segments(count: 10)
        let request = PinRequest(reason: .manual, eventTime: Self.t(40), eventRef: nil)
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 5,
            post: 5,
            segments: segs,
            now: Self.t(300),
            rideStart: Self.rideStart
        )
        #expect(window.segmentIds == [Self.id(2)])
        #expect(window.inOffset == 5)
        #expect(window.outOffset == 15)
    }

    // MARK: - CW-3: clamped at ride start (less than `pre` available)

    @Test func cw3_clampedAtRideStart() {
        // Event at 10 s, manual pre 30 / post 15 ⇒ wanted [−20, 25] but the
        // ride started at 0. Clamp the keep-set/offset to the earliest segment.
        let segs = Self.segments(count: 10)
        let request = PinRequest(reason: .manual, eventTime: Self.t(10), eventRef: nil)
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 30,
            post: 15,
            segments: segs,
            now: Self.t(300),
            rideStart: Self.rideStart
        )
        // Window [0,25] ⇒ segments 0 ([0,15]) and 1 ([15,30]).
        #expect(window.segmentIds == [Self.id(0), Self.id(1)])
        #expect(window.inOffset == 0) // clamped to ride start
        #expect(window.outOffset == 25) // 25 s - segment0 start (0)
        #expect(window.truncatedAtRideStart == true)
    }

    // MARK: - CW-4: post-roll in the future sets pendingUntil

    @Test func cw4_futurePostRollSetsPendingUntil() {
        // 8 segments exist (0…120 s). Event at 110 s, manual post 15 ⇒ the
        // post-roll ends at 125 s, which is after `now` = 118 s.
        let segs = Self.segments(count: 8)
        let request = PinRequest(reason: .manual, eventTime: Self.t(110), eventRef: nil)
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 30,
            post: 15,
            segments: segs,
            now: Self.t(118),
            rideStart: Self.rideStart
        )
        // Post-roll end (125 s) is in the future → pendingUntil set.
        #expect(window.pendingUntil == Self.t(125))
        // Covering segments so far include those up to the latest available.
        #expect(window.segmentIds.contains(Self.id(7)))
        #expect(window.isEmpty == false)
    }

    // MARK: - CW-5: ride ends before post-roll completes → use what exists

    @Test func cw5_ridesEndsEarlyUsesWhatExists() {
        // Only 6 segments exist (0…90 s). Event at 85 s, crash post 30 ⇒ wanted
        // up to 115 s but the latest segment ends at 90 s. now = 300 (ride over).
        let segs = Self.segments(count: 6)
        let request = PinRequest(reason: .crash, eventTime: Self.t(85), eventRef: "crash-1")
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 60,
            post: 30,
            segments: segs,
            now: Self.t(300),
            rideStart: Self.rideStart
        )
        // Keep from [25,90]. Segment 1 starts at 15 (covers 25), … segment 5
        // ends at 90. So segments 1…5.
        #expect(window.segmentIds == (1...5).map(Self.id))
        // pendingUntil is nil because now (300 s) is past the wanted post-roll.
        #expect(window.pendingUntil == nil)
        // out-point clamped to what exists (90 s), measured from segment 1 (15 s).
        #expect(window.outOffset == 75) // 90 - 15
    }

    // MARK: - CW-6: a gap inside the window flags the clip

    @Test func cw6_gapInsideWindowFlagsClip() {
        // Segment 5 has a gap before it (interruption). Event at 80 s, pre 30 /
        // post 15 ⇒ [50,95] spans segments 3…6; segment 5 carries the gap.
        let segs = Self.segments(count: 10, gapBeforeIndex: 5)
        let request = PinRequest(reason: .manual, eventTime: Self.t(80), eventRef: nil)
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 30,
            post: 15,
            segments: segs,
            now: Self.t(300),
            rideStart: Self.rideStart
        )
        #expect(window.hasGap == true)
        #expect(window.segmentIds.contains(Self.id(5)))
    }

    // MARK: - CW-7: no segments in the window → empty (nothing to save)

    @Test func cw7_noSegmentsInWindowIsEmpty() {
        let request = PinRequest(reason: .manual, eventTime: Self.t(40), eventRef: nil)
        let window = ClipWindowPolicy.window(
            for: request,
            pre: 30,
            post: 15,
            segments: [],
            now: Self.t(300),
            rideStart: Self.rideStart
        )
        #expect(window.isEmpty)
        #expect(window.segmentIds.isEmpty)
    }

    // MARK: - CW-8: coalesce an overlapping window into an existing clip

    @Test func cw8_coalesceOverlappingWindow() {
        // Existing saved clip spanning [30,60] with reason manual.
        let existing = ClipRecord(
            id: Self.id(100),
            rideId: Self.rideID,
            reasons: [.manual],
            createdAt: Self.t(60),
            start: Self.t(30),
            end: Self.t(60),
            inOffset: 0,
            outOffset: 30,
            durationSeconds: 30,
            bytes: 60_000_000,
            thumbnailPath: nil,
            hasAudio: false,
            state: .saved,
            hasGap: false,
            eventRef: nil,
            expiresAt: Self.t(100000)
        )
        // New detection window [55,80] overlaps the existing [30,60].
        let decision = ClipCoalescing.coalesce(
            newStart: Self.t(55),
            newEnd: Self.t(80),
            newReasons: [.detection],
            existingClips: [existing],
            coalesceGap: 5,
            maxClipDuration: 180
        )
        guard case let .merge(clipId, unionStart, unionEnd, mergedReasons) = decision else {
            Issue.record("expected a merge decision")
            return
        }
        #expect(clipId == Self.id(100))
        #expect(unionStart == Self.t(30))
        #expect(unionEnd == Self.t(80))
        #expect(mergedReasons == Set<ClipReason>([.manual, .detection]))
    }

    // MARK: - CW-9: near-adjacent (within gap) coalesces; beyond gap is new

    @Test func cw9_nearAdjacentCoalescesBeyondGapIsNew() {
        let existing = ClipRecord(
            id: Self.id(101),
            rideId: Self.rideID,
            reasons: [.manual],
            createdAt: Self.t(60),
            start: Self.t(30),
            end: Self.t(60),
            inOffset: 0,
            outOffset: 30,
            durationSeconds: 30,
            bytes: 60_000_000,
            thumbnailPath: nil,
            hasAudio: false,
            state: .saved,
            hasGap: false,
            eventRef: nil,
            expiresAt: Self.t(100000)
        )
        // New window starts 3 s after the existing end (gap tolerance 5) → merge.
        let near = ClipCoalescing.coalesce(
            newStart: Self.t(63),
            newEnd: Self.t(90),
            newReasons: [.manual],
            existingClips: [existing],
            coalesceGap: 5,
            maxClipDuration: 180
        )
        guard case let .merge(_, _, nearEnd, _) = near else {
            Issue.record("expected a merge for a near-adjacent window")
            return
        }
        #expect(nearEnd == Self.t(90))

        // New window starts 10 s after the existing end (> gap 5) → new clip.
        let far = ClipCoalescing.coalesce(
            newStart: Self.t(70),
            newEnd: Self.t(95),
            newReasons: [.manual],
            existingClips: [existing],
            coalesceGap: 5,
            maxClipDuration: 180
        )
        guard case .new = far else {
            Issue.record("expected a new clip beyond the coalesce gap")
            return
        }
    }

    // MARK: - CW-10: coalescing is capped at the maximum clip duration

    @Test func cw10_coalesceCappedAtMaxClipDuration() {
        // Existing clip already 170 s long [0,170]; max clip duration 180.
        let existing = ClipRecord(
            id: Self.id(102),
            rideId: Self.rideID,
            reasons: [.manual],
            createdAt: Self.t(170),
            start: Self.t(0),
            end: Self.t(170),
            inOffset: 0,
            outOffset: 170,
            durationSeconds: 170,
            bytes: 340_000_000,
            thumbnailPath: nil,
            hasAudio: false,
            state: .saved,
            hasGap: false,
            eventRef: nil,
            expiresAt: Self.t(100000)
        )
        // Overlapping new window [165,200] would make the union 200 s > 180 cap.
        let decision = ClipCoalescing.coalesce(
            newStart: Self.t(165),
            newEnd: Self.t(200),
            newReasons: [.detection],
            existingClips: [existing],
            coalesceGap: 5,
            maxClipDuration: 180
        )
        // Union exceeds the cap → a new clip rather than an over-long merge.
        guard case .new = decision else {
            Issue.record("expected a new clip when the union exceeds the max duration")
            return
        }
    }

    // MARK: - extra: pinned-cap handling (manual allowed; auto refused)

    @Test func pinnedCapRefusesAutoAllowsManualWithRoom() {
        // Cap leaves 50 MB of room; an auto clip is refused, a manual is allowed.
        let roomBytes: Int64 = 50_000_000
        #expect(
            ClipCoalescing.allowsPin(
                reason: .detection,
                estimatedBytes: 16_000_000,
                freeBytesUnderCap: roomBytes
            ) == true
        )
        // No room left under the cap.
        #expect(
            ClipCoalescing.allowsPin(
                reason: .detection,
                estimatedBytes: 16_000_000,
                freeBytesUnderCap: 0
            ) == false
        )
        // Manual is allowed as long as the cap leaves any room.
        #expect(
            ClipCoalescing.allowsPin(
                reason: .manual,
                estimatedBytes: 28_000_000,
                freeBytesUnderCap: 1
            ) == true
        )
        // Manual refused only when the cap leaves no room at all.
        #expect(
            ClipCoalescing.allowsPin(
                reason: .manual,
                estimatedBytes: 28_000_000,
                freeBytesUnderCap: 0
            ) == false
        )
    }
}
