import Foundation

/// Reports the free space usable for important data (rear-camera spec
/// Requirement 12.2, design capability row 12). Put behind a protocol so the
/// `StoragePolicy` input that `FileSegmentStore.freeSpace()` returns is
/// injectable in tests without a real volume.
///
/// The live implementation reads
/// `URLResourceValues.volumeAvailableCapacityForImportantUsage` for a URL on the
/// camera volume (more realistic than raw available capacity); a fake returns a
/// scripted value so storage-guard behaviour is deterministic.
///
/// Foundation-only. `Sendable` because it may be read off the main actor.
protocol FreeSpaceReporting: Sendable {
    /// Free bytes usable for important data on the volume backing `url`.
    /// Returns `0` if the value cannot be read (the storage guard then treats
    /// the volume as full — the safe direction, which stops recording rather
    /// than overfilling the disk).
    func freeBytes(for url: URL) -> Int64
}

/// Live `FreeSpaceReporting` over `URLResourceValues`.
///
/// `volumeAvailableCapacityForImportantUsage` reports the space the system
/// considers usable for important data (it may exceed the raw free bytes because
/// the OS can purge caches), which is the measure the design chose for the
/// storage guard.
struct VolumeFreeSpaceReporter: FreeSpaceReporting {
    init() {}

    func freeBytes(for url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            // The API returns an `Int64?` (bytes); treat an absent value as 0 so
            // the storage guard errs toward stopping recording.
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
}
