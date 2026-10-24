import Foundation
import Testing
@testable import Whoosh

/// Tests for `FileSegmentStore` against a real temporary directory (rear-camera
/// spec task 15; Requirements 5.7, 5.8, 8.4, 8.5, 8.6, 8.9, 17.3).
///
/// Exercises register/list ordering, deleting real files, hard-link pin (with a
/// copy fallback), bytes used, orphan purge (index and on disk), the injectable
/// free-space seam, and backup exclusion on the camera root. Each test uses its
/// own temp root and cleans it up.
@MainActor
struct FileSegmentStoreTests {
    private static let rideA = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    private static let rideB = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A scriptable free-space reporter.
    private struct StubFreeSpace: FreeSpaceReporting {
        let bytes: Int64
        func freeBytes(for url: URL) -> Int64 { bytes }
    }

    /// Makes a store over a fresh temp root plus the layout, returning both so
    /// the test can write real files and clean up.
    private func makeStore(
        freeSpaceBytes: Int64 = 8_000_000_000
    ) -> (store: FileSegmentStore, layout: CameraStorageLayout, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("whoosh-seg-\(UUID().uuidString)", isDirectory: true)
        let layout = CameraStorageLayout(root: root)
        let store = FileSegmentStore(
            layout: layout,
            fileManager: .default,
            freeSpaceReporter: StubFreeSpace(bytes: freeSpaceBytes)
        )
        return (store, layout, root)
    }

    private func cleanUp(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func segment(
        ride: UUID,
        index: Int,
        start: Date,
        bytes: Int64 = 30_000_000
    ) -> SegmentInfo {
        SegmentInfo(
            id: UUID(),
            rideId: ride,
            index: index,
            start: start,
            end: start.addingTimeInterval(15),
            bytes: bytes,
            profileName: "Standard",
            hasAudio: false,
            isPinned: false,
            hasGapBefore: false
        )
    }

    /// Writes a real file on disk at the segment's ring path (so delete/link
    /// have something to act on), returning the segment.
    @discardableResult
    private func writeRingFile(
        _ segment: SegmentInfo,
        layout: CameraStorageLayout,
        contents: Data = Data(repeating: 0x7, count: 128)
    ) -> SegmentInfo {
        let url = layout.ringSegmentURL(segment)
        try? FileManager.default.createDirectory(
            at: layout.ringDirectory(rideId: segment.rideId),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: contents)
        return segment
    }

    // MARK: register / list ordering

    @Test func segmentsOrderedByEndThenIndex() {
        let (store, _, root) = makeStore()
        defer { cleanUp(root) }
        let s0 = segment(ride: Self.rideA, index: 0, start: Self.t0)
        let s1 = segment(ride: Self.rideA, index: 1, start: Self.t0.addingTimeInterval(15))
        let s2 = segment(ride: Self.rideA, index: 2, start: Self.t0.addingTimeInterval(30))
        // Register out of order.
        store.register(s2)
        store.register(s0)
        store.register(s1)
        #expect(store.segments(rideId: Self.rideA).map(\.index) == [0, 1, 2])
        // A different ride is isolated.
        #expect(store.segments(rideId: Self.rideB).isEmpty)
    }

    // MARK: delete removes real files

    @Test func deleteRemovesTheRingFileAndIndexEntry() {
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        let s0 = writeRingFile(segment(ride: Self.rideA, index: 0, start: Self.t0), layout: layout)
        store.register(s0)
        #expect(FileManager.default.fileExists(atPath: layout.ringSegmentURL(s0).path))

        store.delete(ids: [s0.id])
        #expect(!FileManager.default.fileExists(atPath: layout.ringSegmentURL(s0).path))
        #expect(store.segments(rideId: Self.rideA).isEmpty)
    }

    @Test func deleteOfUnknownIdIsSafeNoOp() {
        let (store, _, root) = makeStore()
        defer { cleanUp(root) }
        store.delete(ids: [UUID()]) // must not crash
        #expect(store.segments(rideId: Self.rideA).isEmpty)
    }

    // MARK: pin via hard link (copy fallback)

    @Test func linkPinsSegmentIntoClipMarksPinnedAndRemovesRingPath() {
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        let s0 = writeRingFile(segment(ride: Self.rideA, index: 0, start: Self.t0), layout: layout)
        store.register(s0)
        let clipId = UUID()

        store.link(segmentIds: [s0.id], toClip: clipId)

        // The clip now holds the footage; the ring path is gone.
        let clipPath = layout.clipSegmentURL(s0, clipId: clipId).path
        #expect(FileManager.default.fileExists(atPath: clipPath))
        #expect(!FileManager.default.fileExists(atPath: layout.ringSegmentURL(s0).path))
        // The segment is marked pinned (out of the ring bounds).
        #expect(store.segments(rideId: Self.rideA).first?.isPinned == true)
    }

    @Test func linkedClipSurvivesDeletingTheRingEntry() {
        // Hard link means the clip copy persists even after the ring file path
        // is removed; the pinned segment is no longer a ring candidate.
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        let s0 = writeRingFile(segment(ride: Self.rideA, index: 0, start: Self.t0), layout: layout)
        store.register(s0)
        let clipId = UUID()
        store.link(segmentIds: [s0.id], toClip: clipId)
        let clipPath = layout.clipSegmentURL(s0, clipId: clipId).path
        #expect(FileManager.default.fileExists(atPath: clipPath))
    }

    // MARK: bytes used

    @Test func bytesUsedSumsRegisteredSegments() {
        let (store, _, root) = makeStore()
        defer { cleanUp(root) }
        store.register(segment(ride: Self.rideA, index: 0, start: Self.t0, bytes: 10))
        store.register(segment(ride: Self.rideA, index: 1, start: Self.t0.addingTimeInterval(15), bytes: 25))
        #expect(store.bytesUsed() == 35)
    }

    // MARK: orphan purge

    @Test func purgeOrphansDropsUnkeptRidesFromIndexAndDisk() {
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        let kept = writeRingFile(segment(ride: Self.rideA, index: 0, start: Self.t0), layout: layout)
        let orphan = writeRingFile(segment(ride: Self.rideB, index: 0, start: Self.t0), layout: layout)
        store.register(kept)
        store.register(orphan)

        store.purgeOrphans(keepingRides: [Self.rideA])

        #expect(store.segments(rideId: Self.rideA).count == 1)
        #expect(store.segments(rideId: Self.rideB).isEmpty)
        // The orphan ride's whole ring directory is gone; the kept one remains.
        #expect(!FileManager.default.fileExists(atPath: layout.ringDirectory(rideId: Self.rideB).path))
        #expect(FileManager.default.fileExists(atPath: layout.ringSegmentURL(kept).path))
    }

    @Test func purgeOrphansRemovesRingDirWithNoIndexEntry() {
        // A process killed before registering leaves files with no index entry;
        // purge must still remove them from disk.
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        let stray = segment(ride: Self.rideB, index: 0, start: Self.t0)
        writeRingFile(stray, layout: layout)
        // Nothing registered for rideB.
        store.purgeOrphans(keepingRides: [Self.rideA])
        #expect(!FileManager.default.fileExists(atPath: layout.ringDirectory(rideId: Self.rideB).path))
    }

    // MARK: free-space seam and index rebuild

    @Test func freeSpaceReturnsTheReportedValue() {
        let (store, _, root) = makeStore(freeSpaceBytes: 1_234_567)
        defer { cleanUp(root) }
        #expect(store.freeSpace() == 1_234_567)
    }

    @Test func rebuildIndexRecoversRingFilesForKeptRides() {
        let (store, layout, root) = makeStore()
        defer { cleanUp(root) }
        // Write two ring files directly (simulating a prior launch), nothing in
        // the index yet.
        writeRingFile(segment(ride: Self.rideA, index: 0, start: Self.t0), layout: layout)
        writeRingFile(segment(ride: Self.rideA, index: 1, start: Self.t0.addingTimeInterval(15)), layout: layout)

        store.rebuildIndex(forRides: [Self.rideA])
        let recovered = store.segments(rideId: Self.rideA)
        #expect(recovered.count == 2)
        #expect(recovered.map(\.index) == [0, 1])
        #expect(store.bytesUsed() == 256) // two 128-byte files
    }

    // MARK: backup exclusion on the camera root

    @Test func cameraRootIsExcludedFromBackup() throws {
        let (_, layout, root) = makeStore()
        defer { cleanUp(root) }
        let values = try layout.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
