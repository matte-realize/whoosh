import Foundation

/// In-memory `SegmentStore` for tests and SwiftUI previews: the segment index is
/// a dictionary and `freeSpace()` is a scriptable value, so ring-buffer and
/// pinning logic (tasks 16/19) can be exercised without the file system.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - Seed with `register(_:)` or the `segments:` initializer.
/// - Set `freeSpaceBytes` to drive the `StoragePolicy` input.
/// - `link(...)` flips `isPinned` on the referenced segments and records the
///   clip link for assertions; `delete(...)` and `purgeOrphans(...)` mutate the
///   index. All behaviour is synchronous and deterministic.
@MainActor
final class InMemorySegmentStore: SegmentStore {
    /// Free space reported by `freeSpace()`; set to drive storage policy tests.
    var freeSpaceBytes: Int64

    // MARK: Recorded interactions (for test assertions)

    /// Clip links recorded by `link(...)`: clip id → the segment ids linked.
    private(set) var clipLinks: [UUID: [UUID]] = [:]
    /// Ride ids passed to the most recent `purgeOrphans`.
    private(set) var lastPurgeKeptRides: Set<UUID>?

    private var index: [UUID: SegmentInfo] = [:]

    init(segments: [SegmentInfo] = [], freeSpaceBytes: Int64 = 8_000_000_000) {
        self.freeSpaceBytes = freeSpaceBytes
        for segment in segments { index[segment.id] = segment }
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
        for id in ids { index[id] = nil }
    }

    func link(segmentIds: [UUID], toClip clipId: UUID) {
        clipLinks[clipId, default: []].append(contentsOf: segmentIds)
        for id in segmentIds {
            index[id]?.isPinned = true
        }
    }

    func bytesUsed() -> Int64 {
        index.values.reduce(0) { $0 + $1.bytes }
    }

    func purgeOrphans(keepingRides: Set<UUID>) {
        lastPurgeKeptRides = keepingRides
        for (id, segment) in index where !keepingRides.contains(segment.rideId) {
            index[id] = nil
        }
    }

    func freeSpace() -> Int64 { freeSpaceBytes }

    // MARK: Test helpers

    /// All registered segments across rides, ordered by ride then end time.
    var allSegments: [SegmentInfo] {
        index.values.sorted { lhs, rhs in
            lhs.end == rhs.end ? lhs.index < rhs.index : lhs.end < rhs.end
        }
    }

    /// The pinned state of a segment, or `nil` if it is not registered.
    func isPinned(_ id: UUID) -> Bool? { index[id]?.isPinned }
}
