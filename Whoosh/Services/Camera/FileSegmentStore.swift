import Foundation
import OSLog

/// File-backed `SegmentStore` (rear-camera spec task 15; Requirements 5.7, 5.8,
/// 8.4, 8.5, 8.6, 8.9, 17.3). Owns the on-disk ring/clip layout, maps each
/// `SegmentInfo` to a file via `CameraStorageLayout`, and keeps an in-memory
/// index rebuilt from the files on launch.
///
/// ## Contract (non-negotiable; see privacy steering and the design)
/// - **On-device only.** Footage lives under the camera root, excluded from
///   backups (`isExcludedFromBackup`) and written with a protection class that
///   still allows writing while the device is locked after first unlock
///   (`.completeUntilFirstUserAuthentication`). Nothing here uploads, links,
///   logs, or transmits a segment path or its contents.
/// - **Pinning uses hard links.** `link(segmentIds:toClip:)` hard-links each
///   segment into `clips/<clipID>/` (APFS `linkItem`), copying only if linking
///   fails, marks it pinned so it no longer counts toward the ring bounds, and
///   removes the ring path. The clip keeps the footage even as the ring evicts.
/// - **Orphans purged on launch.** `purgeOrphans(keepingRides:)` removes ring
///   directories whose ride is not one of `keepingRides` (app killed mid-ride).
/// - **Never blocks capture.** Registration/deletion run on the main actor, off
///   the capture queue; the recorder writes files on its own queue and only the
///   finished `SegmentInfo` crosses back.
///
/// `@MainActor` to match the `SegmentStore` protocol and the project's default
/// isolation; file I/O here is small metadata work (create dir, link, remove),
/// not the hot capture path.
@MainActor
final class FileSegmentStore: SegmentStore {
    private let layout: CameraStorageLayout
    private let fileManager: FileManager
    private let freeSpaceReporter: FreeSpaceReporting
    private static let logger = Logger(subsystem: "com.whoosh.app", category: "FileSegmentStore")

    /// The in-memory segment index, keyed by id. Rebuilt from files on launch
    /// via `rebuildIndex(forRides:)`.
    private var index: [UUID: SegmentInfo] = [:]
    /// The file extension the recorder writes (mp4). Kept here so path mapping
    /// stays in one place.
    private let fileExtension = "mp4"

    /// - Parameters:
    ///   - layout: the on-disk layout (root directory). Defaults to the
    ///     Application Support camera root.
    ///   - fileManager: injected for tests over a temp directory.
    ///   - freeSpaceReporter: the free-space query behind a protocol.
    init(
        layout: CameraStorageLayout = CameraStorageLayout(root: CameraStorageLayout.defaultRoot()),
        fileManager: FileManager = .default,
        freeSpaceReporter: FreeSpaceReporting = VolumeFreeSpaceReporter()
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.freeSpaceReporter = freeSpaceReporter
        createCameraRootIfNeeded()
    }

    // MARK: SegmentStore

    func register(_ segment: SegmentInfo) {
        index[segment.id] = segment
    }

    func segments(rideId: UUID) -> [SegmentInfo] {
        index.values
            .filter { $0.rideId == rideId }
            .sorted { lhs, rhs in
                lhs.end == rhs.end ? lhs.index < rhs.index : lhs.end < rhs.end
            }
    }

    func delete(ids: [UUID]) {
        for id in ids {
            guard let segment = index[id] else { continue }
            removeFileIfPresent(at: layout.ringSegmentURL(segment, fileExtension: fileExtension))
            index[id] = nil
        }
    }

    func link(segmentIds: [UUID], toClip clipId: UUID) {
        let clipDir = layout.clipDirectory(clipId: clipId)
        createDirectory(clipDir)
        for id in segmentIds {
            guard var segment = index[id] else { continue }
            let source = layout.ringSegmentURL(segment, fileExtension: fileExtension)
            let destination = layout.clipSegmentURL(segment, clipId: clipId, fileExtension: fileExtension)
            linkOrCopy(from: source, to: destination)
            // Mark pinned (out of the ring bounds) and remove the ring path so
            // the clip is the only remaining strong reference to the footage.
            segment.isPinned = true
            index[id] = segment
            removeFileIfPresent(at: source)
        }
    }

    func bytesUsed() -> Int64 {
        index.values.reduce(0) { $0 + $1.bytes }
    }

    func purgeOrphans(keepingRides: Set<UUID>) {
        // Drop index entries whose ride is not retained.
        for (id, segment) in index where !keepingRides.contains(segment.rideId) {
            index[id] = nil
        }
        // Remove ring directories on disk whose ride is not retained (covers
        // files left by a process that was killed before registering them).
        let ringRoot = layout.ringRoot
        guard let rideDirs = try? fileManager.contentsOfDirectory(
            at: ringRoot,
            includingPropertiesForKeys: nil
        ) else { return }
        for dir in rideDirs {
            let name = dir.lastPathComponent
            if let rideId = UUID(uuidString: name), keepingRides.contains(rideId) {
                continue
            }
            removeFileIfPresent(at: dir)
        }
    }

    func freeSpace() -> Int64 {
        freeSpaceReporter.freeBytes(for: layout.root)
    }

    // MARK: Index rebuild (launch)

    /// Rebuild the in-memory index from the ring directories on disk for the
    /// given rides, so the ring is bounded correctly after a relaunch. A file
    /// whose name cannot be parsed, or whose attributes cannot be read, is
    /// skipped (and logged) rather than throwing. Ring files for rides not in
    /// `rides` are left for `purgeOrphans(keepingRides:)` to remove.
    func rebuildIndex(forRides rides: Set<UUID>) {
        index.removeAll()
        for rideId in rides {
            let dir = layout.ringDirectory(rideId: rideId)
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for file in files where file.pathExtension == fileExtension {
                guard let segment = segmentInfo(from: file, rideId: rideId) else {
                    Self.logger.error("Skipping unparseable ring file \(file.lastPathComponent, privacy: .public)")
                    continue
                }
                index[segment.id] = segment
            }
        }
    }

    // MARK: - File helpers

    private func segmentInfo(from file: URL, rideId: UUID) -> SegmentInfo? {
        // Name: seg-<index>-<startEpochMs>.mp4
        let name = file.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        guard parts.count == 3, parts[0] == "seg",
              let idx = Int(parts[1]), let startMs = Int64(parts[2]) else {
            return nil
        }
        let start = Date(timeIntervalSince1970: Double(startMs) / 1000)
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        // End is unknown from the file name alone; use the start as a floor. The
        // live index carries the true end; a rebuilt-on-launch index is only
        // used to bound and purge the ring, where a conservative end is safe.
        return SegmentInfo(
            id: UUID(),
            rideId: rideId,
            index: idx,
            start: start,
            end: start,
            bytes: bytes,
            profileName: CaptureProfile.standard.name,
            hasAudio: false,
            isPinned: false,
            hasGapBefore: false
        )
    }

    private func createCameraRootIfNeeded() {
        createDirectory(layout.root)
        // Exclude the whole camera tree from backups (footage never leaves the
        // device, including via iCloud/iTunes backups).
        excludeFromBackup(layout.root)
    }

    private func createDirectory(_ url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            excludeFromBackup(url)
            applyProtection(url)
        } catch {
            Self.logger.error("Failed to create camera directory \(url.lastPathComponent, privacy: .public)")
        }
    }

    private func excludeFromBackup(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    /// Apply a protection class that allows writing after the first unlock even
    /// when the device is later locked (capability row 13). Verified on device
    /// in task 31; on the simulator `setAttributes` is a harmless no-op.
    private func applyProtection(_ url: URL) {
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func linkOrCopy(from source: URL, to destination: URL) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        // A stale destination would make linkItem/copyItem throw; clear it first.
        removeFileIfPresent(at: destination)
        do {
            try fileManager.linkItem(at: source, to: destination)
        } catch {
            // Copy fallback when hard-linking is not possible (e.g. across
            // volumes, or a file system without APFS hard links).
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                Self.logger.error("Failed to pin segment file (link and copy both failed)")
            }
        }
    }

    private func removeFileIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
