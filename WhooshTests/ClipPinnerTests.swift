import Foundation
import Testing
@testable import Whoosh

/// Tests for `ClipPinner` (rear-camera spec task 16; Requirements 6.1–6.9, 8.4,
/// 8.5, 8.7). Written test-first from the design's "Pinning" contract and the
/// MAN-1…4 / CL-1…6 cases.
///
/// Uses the in-memory segment store and clip repository, the fake thumbnailer,
/// a `TestClock`, and a temp-root layout (no real files needed: the fake
/// thumbnailer only records URLs). `@MainActor` to match the pinner/stores.
@MainActor
struct ClipPinnerTests {
    private static let rideID = UUID(uuidString: "00000000-0000-0000-0000-00000000CAFE")!
    private static let rideStart = Date(timeIntervalSince1970: 2_000_000)
    private static let segmentLength: TimeInterval = 15

    private func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    /// Contiguous 15 s segments 0…count-1 from the ride start.
    private func segments(count: Int, gapBeforeIndex: Int? = nil) -> [SegmentInfo] {
        (0..<count).map { i in
            let start = Self.rideStart.addingTimeInterval(Double(i) * Self.segmentLength)
            return SegmentInfo(
                id: id(i),
                rideId: Self.rideID,
                index: i,
                start: start,
                end: start.addingTimeInterval(Self.segmentLength),
                bytes: 30_000_000,
                profileName: "Standard",
                hasAudio: false,
                isPinned: false,
                hasGapBefore: gapBeforeIndex == i
            )
        }
    }

    private func t(_ seconds: TimeInterval) -> Date {
        Self.rideStart.addingTimeInterval(seconds)
    }

    private func makePinner(
        segments segs: [SegmentInfo] = [],
        clips: [ClipRecord] = [],
        thumbnailer: FakeClipThumbnailer = FakeClipThumbnailer(),
        clock: TestClock
    ) -> (pinner: ClipPinner, store: InMemorySegmentStore, repo: InMemoryClipRepository, thumb: FakeClipThumbnailer) {
        let store = InMemorySegmentStore(segments: segs)
        let repo = InMemoryClipRepository(clips: clips)
        let layout = CameraStorageLayout(
            root: FileManager.default.temporaryDirectory.appendingPathComponent("whoosh-pin-\(UUID().uuidString)")
        )
        let pinner = ClipPinner(
            segmentStore: store,
            clipRepository: repo,
            thumbnailer: thumbnailer,
            layout: layout,
            tuning: RideCameraTuning(),
            clock: clock
        )
        return (pinner, store, repo, thumbnailer)
    }

    // MARK: - MAN-1: a manual save with footage produces a saved clip

    @Test func man1_manualSaveProducesSavedClip() async throws {
        // now is well past the post-roll so the clip saves immediately.
        let clock = TestClock(now: t(300))
        let (pinner, store, repo, thumb) = makePinner(segments: segments(count: 20), clock: clock)

        let result = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))

        guard case let .saved(clipId) = result else {
            Issue.record("expected .saved, got \(result)")
            return
        }
        let clips = try repo.clips(rideId: Self.rideID)
        #expect(clips.count == 1)
        #expect(clips.first?.id == clipId)
        #expect(clips.first?.state == .saved)
        #expect(clips.first?.reasons == [.manual])
        // Kept segments are pinned and a thumbnail was requested.
        #expect(store.allSegments.contains { $0.isPinned })
        #expect(await thumb.requestCount == 1)
        #expect(clips.first?.thumbnailPath != nil)
    }

    // MARK: - MAN-2: debounce ignores a second save inside the window

    @Test func man2_debounceIgnoresRapidSecondSave() async {
        let clock = TestClock(now: t(300))
        let (pinner, _, repo, _) = makePinner(segments: segments(count: 20), clock: clock)

        _ = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))
        // Within the 2 s debounce window.
        clock.advance(by: 1)
        let second = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(110))
        #expect(second == .debounced)
        #expect((try? repo.clips(rideId: Self.rideID).count) == 1)

        // After the debounce elapses, a save is accepted again.
        clock.advance(by: 2)
        let third = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(130))
        if case .debounced = third { Issue.record("third save should not be debounced") }
    }

    // MARK: - MAN-3: nothing to save when there are no segments

    @Test func man3_nothingToSaveWithoutSegments() async {
        let clock = TestClock(now: t(300))
        let (pinner, _, repo, _) = makePinner(segments: [], clock: clock)
        let result = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))
        #expect(result == .notSaved(.nothingToSave))
        #expect((try? repo.clips(rideId: Self.rideID).isEmpty) == true)
    }

    // MARK: - MAN-4: storage-full refuses an auto-pin but a manual save squeezes in

    @Test func man4_storageFullRefusesAutoPinButAllowsManual() async {
        let clock = TestClock(now: t(300))
        var tuning = RideCameraTuning()
        tuning.pinnedMaxBytes = 10 // effectively full
        let store = InMemorySegmentStore(segments: segments(count: 20))
        let repo = InMemoryClipRepository()
        let layout = CameraStorageLayout(
            root: FileManager.default.temporaryDirectory.appendingPathComponent("whoosh-pin-\(UUID().uuidString)")
        )
        let pinner = ClipPinner(
            segmentStore: store, clipRepository: repo,
            thumbnailer: FakeClipThumbnailer(), layout: layout, tuning: tuning, clock: clock
        )

        // Auto-pin needs the whole estimate to fit ⇒ refused.
        let auto = await pinner.pin(
            PinRequest(reason: .detection, eventTime: t(100), eventRef: "nm-1"),
            rideId: Self.rideID, rideStart: Self.rideStart
        )
        #expect(auto == .notSaved(.storageFull))

        // Manual is allowed while any room remains under the cap (>0 bytes free).
        let manual = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))
        if case .notSaved = manual { Issue.record("manual save should squeeze in under the cap") }
    }

    // MARK: - CL-1: a future post-roll yields a pending clip, finalized later

    @Test func cl1_pendingClipFinalizesAtRideEnd() async throws {
        // Event at t=150 with manual post-roll 15 s ⇒ post-roll ends at t=165.
        // now = t=160 (post-roll still in the future) ⇒ pending.
        let clock = TestClock(now: t(160))
        let (pinner, _, repo, thumb) = makePinner(segments: segments(count: 12), clock: clock)

        let result = await pinner.pin(
            PinRequest(reason: .manual, eventTime: t(150), eventRef: nil),
            rideId: Self.rideID, rideStart: Self.rideStart
        )
        guard case let .pending(clipId) = result else {
            Issue.record("expected .pending, got \(result)")
            return
        }
        #expect(try repo.clip(id: clipId)?.state == .pending)
        // No thumbnail yet for a pending clip.
        #expect(await thumb.requestCount == 0)

        // Ride ends after the post-roll completed ⇒ flips to saved + thumbnail.
        clock.advance(by: 20) // now t=180, past the clip end (t=180 for 12 segs)
        await pinner.finalizePending(rideId: Self.rideID)
        #expect(try repo.clip(id: clipId)?.state == .saved)
        #expect(await thumb.requestCount == 1)
    }

    // MARK: - CL-2: coalescing merges a near-adjacent save into an existing clip

    @Test func cl2_coalesceMergesIntoExistingClip() async throws {
        let clock = TestClock(now: t(400))
        let (pinner, _, repo, _) = makePinner(segments: segments(count: 30), clock: clock)

        // First manual save around t=100.
        let first = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))
        guard case let .saved(firstId) = first else {
            Issue.record("expected first .saved, got \(first)")
            return
        }
        clock.advance(by: 5) // clear the debounce
        // A second save close enough to coalesce (windows within the gap).
        let second = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(110))
        #expect(second == .merged(firstId))
        // Still one clip, carrying the manual reason.
        let clips = try repo.clips(rideId: Self.rideID)
        #expect(clips.count == 1)
        #expect(clips.first?.reasons.contains(.manual) == true)
    }

    // MARK: - CL-3: retention sweep deletes expired clips

    @Test func cl3_retentionSweepDeletesExpired() throws {
        let clock = TestClock(now: t(1000))
        let expiredClip = ClipRecord(
            id: UUID(), rideId: Self.rideID, reasons: [.manual],
            createdAt: t(0), start: t(0), end: t(45),
            inOffset: 0, outOffset: 45, durationSeconds: 45, bytes: 10,
            thumbnailPath: nil, hasAudio: false, state: .saved, hasGap: false,
            eventRef: nil, expiresAt: t(500) // already expired at now=t(1000)
        )
        let liveClip = ClipRecord(
            id: UUID(), rideId: Self.rideID, reasons: [.manual],
            createdAt: t(0), start: t(0), end: t(45),
            inOffset: 0, outOffset: 45, durationSeconds: 45, bytes: 10,
            thumbnailPath: nil, hasAudio: false, state: .saved, hasGap: false,
            eventRef: nil, expiresAt: t(5_000_000) // far future
        )
        let (pinner, _, repo, _) = makePinner(clips: [expiredClip, liveClip], clock: clock)

        pinner.sweepExpired()
        let remaining = try repo.clips(rideId: Self.rideID).map(\.id)
        #expect(remaining == [liveClip.id])
    }

    // MARK: - CL-4: ride-deletion cascade removes every clip for the ride

    @Test func cl4_deleteClipsForRideCascades() throws {
        let clock = TestClock(now: t(400))
        let otherRide = UUID()
        let c1 = ClipRecord(
            id: UUID(), rideId: Self.rideID, reasons: [.manual], createdAt: t(0),
            start: t(0), end: t(45), inOffset: 0, outOffset: 45, durationSeconds: 45,
            bytes: 10, thumbnailPath: nil, hasAudio: false, state: .saved,
            hasGap: false, eventRef: nil, expiresAt: t(5_000_000)
        )
        let c2 = ClipRecord(
            id: UUID(), rideId: otherRide, reasons: [.manual], createdAt: t(0),
            start: t(0), end: t(45), inOffset: 0, outOffset: 45, durationSeconds: 45,
            bytes: 10, thumbnailPath: nil, hasAudio: false, state: .saved,
            hasGap: false, eventRef: nil, expiresAt: t(5_000_000)
        )
        let (pinner, _, repo, _) = makePinner(clips: [c1, c2], clock: clock)

        pinner.deleteClips(forRide: Self.rideID)
        #expect(try repo.clips(rideId: Self.rideID).isEmpty)
        #expect(try repo.clips(rideId: otherRide).count == 1)
    }

    // MARK: - CL-5: deleting one clip removes only that record

    @Test func cl5_deleteOneClip() throws {
        let clock = TestClock(now: t(400))
        let c1 = ClipRecord(
            id: UUID(), rideId: Self.rideID, reasons: [.manual], createdAt: t(0),
            start: t(0), end: t(45), inOffset: 0, outOffset: 45, durationSeconds: 45,
            bytes: 10, thumbnailPath: nil, hasAudio: false, state: .saved,
            hasGap: false, eventRef: nil, expiresAt: t(5_000_000)
        )
        let c2 = ClipRecord(
            id: UUID(), rideId: Self.rideID, reasons: [.manual], createdAt: t(10),
            start: t(0), end: t(45), inOffset: 0, outOffset: 45, durationSeconds: 45,
            bytes: 10, thumbnailPath: nil, hasAudio: false, state: .saved,
            hasGap: false, eventRef: nil, expiresAt: t(5_000_000)
        )
        let (pinner, _, repo, _) = makePinner(clips: [c1, c2], clock: clock)

        pinner.deleteClip(id: c1.id)
        #expect(try repo.clips(rideId: Self.rideID).map(\.id) == [c2.id])
    }

    // MARK: - CL-6: a thumbnail failure never blocks saving the clip

    @Test func cl6_thumbnailFailureStillSavesClip() async throws {
        let clock = TestClock(now: t(300))
        let failing = FakeClipThumbnailer(succeeds: false)
        let (pinner, _, repo, _) = makePinner(segments: segments(count: 20), thumbnailer: failing, clock: clock)

        let result = await pinner.saveManually(rideId: Self.rideID, rideStart: Self.rideStart, eventTime: t(100))
        guard case let .saved(clipId) = result else {
            Issue.record("expected .saved even when the thumbnail fails, got \(result)")
            return
        }
        let clip = try repo.clip(id: clipId)
        #expect(clip?.state == .saved)
        #expect(clip?.thumbnailPath == nil) // no thumbnail, but the clip is saved
    }
}
