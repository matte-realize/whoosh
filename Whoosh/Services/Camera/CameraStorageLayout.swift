import Foundation

/// The on-disk layout for rear-camera footage (rear-camera spec design
/// "On-disk layout"). One place computes every path so the recorder
/// (`AssetWriterSegmentRecorder`, task 18) and the store (`FileSegmentStore`,
/// task 15) agree on where a segment lives without passing URLs around.
///
/// ```
/// <root>/                                   Application Support/Whoosh/Camera
///   ring/<rideID>/seg-<index>-<startMs>.mp4 unpinned rolling segments
///   clips/<clipID>/seg-<index>-<startMs>.mp4  pinned (hard links, copy fallback)
///   clips/<clipID>/thumb.jpg                a single thumbnail
///   tmp/                                    test recordings, export staging
/// ```
///
/// All footage lives under `<root>`, which is excluded from backups and written
/// with a protection class that still allows writing while locked after first
/// unlock (`FileSegmentStore` applies both). Nothing here uploads, links, or
/// logs a path.
///
/// Foundation-only value type; paths are derived purely from `SegmentInfo`
/// fields so a rebuilt-on-launch index maps back to the same files.
nonisolated struct CameraStorageLayout: Sendable {
    /// The camera root directory (`.../Camera`).
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// The ring directory for a ride (`ring/<rideID>`).
    func ringDirectory(rideId: UUID) -> URL {
        root.appendingPathComponent("ring", isDirectory: true)
            .appendingPathComponent(rideId.uuidString, isDirectory: true)
    }

    /// The directory holding every ring segment (`ring`).
    var ringRoot: URL {
        root.appendingPathComponent("ring", isDirectory: true)
    }

    /// The clips directory (`clips`).
    var clipsRoot: URL {
        root.appendingPathComponent("clips", isDirectory: true)
    }

    /// The directory for one clip's linked segments and thumbnail
    /// (`clips/<clipID>`).
    func clipDirectory(clipId: UUID) -> URL {
        clipsRoot.appendingPathComponent(clipId.uuidString, isDirectory: true)
    }

    /// The temp directory for test recordings and export staging (`tmp`).
    var tempDirectory: URL {
        root.appendingPathComponent("tmp", isDirectory: true)
    }

    /// The file name for a segment: `seg-<index>-<startEpochMs>.<ext>`.
    /// Derived purely from `SegmentInfo` so the index can be rebuilt from files.
    func segmentFileName(index: Int, start: Date, fileExtension: String = "mp4") -> String {
        let startMs = Int64((start.timeIntervalSince1970 * 1000).rounded())
        return "seg-\(index)-\(startMs).\(fileExtension)"
    }

    /// The ring-path URL for a segment.
    func ringSegmentURL(_ segment: SegmentInfo, fileExtension: String = "mp4") -> URL {
        ringDirectory(rideId: segment.rideId)
            .appendingPathComponent(
                segmentFileName(index: segment.index, start: segment.start, fileExtension: fileExtension)
            )
    }

    /// The clip-path URL a segment is linked to inside a clip folder.
    func clipSegmentURL(_ segment: SegmentInfo, clipId: UUID, fileExtension: String = "mp4") -> URL {
        clipDirectory(clipId: clipId)
            .appendingPathComponent(
                segmentFileName(index: segment.index, start: segment.start, fileExtension: fileExtension)
            )
    }

    /// The thumbnail URL for a clip (`clips/<clipID>/thumb.jpg`).
    func thumbnailURL(clipId: UUID) -> URL {
        clipDirectory(clipId: clipId).appendingPathComponent("thumb.jpg")
    }

    /// The default camera root under Application Support, created on first use
    /// by the caller. Falls back to the caches directory if Application Support
    /// is unavailable (recording still works; the files are still on-device).
    static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Whoosh", isDirectory: true)
            .appendingPathComponent("Camera", isDirectory: true)
    }
}
