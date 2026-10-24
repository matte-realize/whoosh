import Foundation

/// Pure clip-coalescing policy for rear-camera pinning (rear-camera spec task 4;
/// Requirements 6.4, 6.6, 6.9). Decides whether a newly requested pin window
/// should **merge** into an existing clip (overlapping or within the coalesce
/// gap, up to the maximum clip duration, keeping every contributing reason) or
/// start a **new** clip, and whether a pin is allowed under the pinned-storage
/// cap (manual saves until the cap is full; auto-pins refused at the cap).
///
/// Framework-free (Metrics layer: Models + Foundation only). It reasons over
/// `ClipRecord` values and wall-clock `Date`s; it never touches files.
enum ClipCoalescing {
    /// The result of deciding where a new window goes.
    enum Decision: Equatable, Sendable {
        /// Merge into the identified clip, growing it to the union range and
        /// carrying the merged reason set.
        case merge(clipId: UUID, unionStart: Date, unionEnd: Date, reasons: Set<ClipReason>)
        /// Start a new clip (no eligible existing clip, or merging would exceed
        /// the maximum clip duration).
        case new
    }

    /// Decides whether `[newStart, newEnd]` merges into an existing clip or
    /// starts a new one. See the type doc for the contract.
    ///
    /// A new window is eligible to merge with an existing clip when their ranges
    /// overlap or are within `coalesceGap` of each other. Among eligible clips
    /// the earliest (by start) is chosen for a deterministic result. The merge
    /// only happens if the union's duration does not exceed `maxClipDuration`;
    /// otherwise a new clip is started (a shared boundary segment is linked into
    /// both by the pinner, outside this pure decision).
    static func coalesce(
        newStart: Date,
        newEnd: Date,
        newReasons: Set<ClipReason>,
        existingClips: [ClipRecord],
        coalesceGap: TimeInterval,
        maxClipDuration: TimeInterval
    ) -> Decision {
        // Eligible existing clips: within the coalesce gap of the new window.
        let eligible = existingClips
            .filter { clip in
                isWithinGap(
                    aStart: clip.start, aEnd: clip.end,
                    bStart: newStart, bEnd: newEnd,
                    gap: coalesceGap
                )
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        guard let target = eligible.first else { return .new }

        let unionStart = min(target.start, newStart)
        let unionEnd = max(target.end, newEnd)
        // Beyond the cap ⇒ a new clip rather than an over-long merge.
        guard unionEnd.timeIntervalSince(unionStart) <= maxClipDuration else {
            return .new
        }

        return .merge(
            clipId: target.id,
            unionStart: unionStart,
            unionEnd: unionEnd,
            reasons: target.reasons.union(newReasons)
        )
    }

    /// Whether a pin of `reason` is allowed given the room left under the
    /// pinned-storage cap. Auto-pins (detection, crash, demo) require the whole
    /// estimated clip to fit; a manual save is allowed as long as the cap leaves
    /// any room at all (Requirement 6.6).
    static func allowsPin(
        reason: ClipReason,
        estimatedBytes: Int64,
        freeBytesUnderCap: Int64
    ) -> Bool {
        switch reason {
        case .manual:
            return freeBytesUnderCap > 0
        case .detection, .crash, .demo:
            return estimatedBytes <= freeBytesUnderCap
        }
    }

    // MARK: - Private

    /// Whether ranges `[aStart,aEnd]` and `[bStart,bEnd]` overlap or come within
    /// `gap` of each other.
    private static func isWithinGap(
        aStart: Date, aEnd: Date,
        bStart: Date, bEnd: Date,
        gap: TimeInterval
    ) -> Bool {
        // Expand range A by `gap` on both sides, then test for overlap with B.
        let expandedStart = aStart.addingTimeInterval(-gap)
        let expandedEnd = aEnd.addingTimeInterval(gap)
        return bStart <= expandedEnd && bEnd >= expandedStart
    }
}
