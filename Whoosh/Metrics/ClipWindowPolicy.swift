import Foundation

/// Pure clip-window computation for rear-camera pinning (rear-camera spec
/// task 4; Requirements 6.2, 6.5, 11.7). Turns a `PinRequest` (plus the pre/post
/// from `RideCameraTuning`, the available segment index, `now`, and the ride
/// start) into a `PinWindow`.
///
/// Framework-free (Metrics layer: Models + Foundation only); it reasons over
/// `SegmentInfo` values and never touches files. Time is wall-clock `Date`,
/// never `CMTime`.
///
/// Contract (design "Pinning and ClipWindowPolicy"):
/// - The wanted window is `[event − pre, event + post]`.
/// - The lower edge is clamped to `rideStart`; if the ride started less than
///   `pre` before the event, `truncatedAtRideStart` is set.
/// - The keep-set is every segment that overlaps `[windowStart, windowEnd]`,
///   snapped outward to whole segment boundaries, bounded above by the latest
///   available segment (so it never invents footage that does not exist yet).
/// - `inOffset`/`outOffset` are exact playback offsets from the first kept
///   segment's start: the in-point is the clamped window start, the out-point is
///   the window end clamped to the last kept segment's end.
/// - `pendingUntil` is `event + post` when that instant is still in the future
///   at `now` (the post-roll is still being recorded); otherwise `nil`.
/// - `hasGap` is true when a kept segment (other than the first) begins after an
///   interruption (`hasGapBefore`), i.e. a recording gap falls inside the clip.
/// - With no overlapping segments the window is empty ("nothing to save").
enum ClipWindowPolicy {
    /// Computes the pin window for a request. See the type doc for the contract.
    /// Never mutates its inputs.
    static func window(
        for request: PinRequest,
        pre: TimeInterval,
        post: TimeInterval,
        segments: [SegmentInfo],
        now: Date,
        rideStart: Date
    ) -> PinWindow {
        let event = request.eventTime
        let wantedStart = event.addingTimeInterval(-pre)
        let wantedEnd = event.addingTimeInterval(post)

        // Clamp the lower edge to the ride start.
        let truncatedAtRideStart = wantedStart < rideStart
        let windowStart = truncatedAtRideStart ? rideStart : wantedStart

        // Post-roll still in the future? The clip stays pending until then.
        let pendingUntil: Date? = wantedEnd > now ? wantedEnd : nil

        // Sort segments by start time so the keep-set is contiguous and ordered.
        let ordered = segments.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.index < rhs.index
        }

        guard let latestEnd = ordered.map(\.end).max() else {
            return emptyWindow(pendingUntil: pendingUntil, truncatedAtRideStart: truncatedAtRideStart)
        }
        // Never keep beyond the footage that actually exists.
        let effectiveEnd = min(wantedEnd, latestEnd)

        // Keep every segment overlapping [windowStart, effectiveEnd): a segment
        // overlaps when it starts before the window end and ends after the
        // window start (half-open so an exactly-abutting segment is excluded).
        let kept = ordered.filter { seg in
            seg.start < effectiveEnd && seg.end > windowStart
        }

        guard let first = kept.first, let last = kept.last else {
            return emptyWindow(pendingUntil: pendingUntil, truncatedAtRideStart: truncatedAtRideStart)
        }

        // Exact playback offsets from the first kept segment's start.
        let inOffset = max(0, windowStart.timeIntervalSince(first.start))
        let outPoint = min(effectiveEnd, last.end)
        let outOffset = outPoint.timeIntervalSince(first.start)

        // A gap inside the window: any kept segment after the first that begins
        // right after an interruption.
        let hasGap = kept.dropFirst().contains { $0.hasGapBefore }

        return PinWindow(
            segmentIds: kept.map(\.id),
            inOffset: inOffset,
            outOffset: outOffset,
            pendingUntil: pendingUntil,
            hasGap: hasGap,
            truncatedAtRideStart: truncatedAtRideStart
        )
    }

    // MARK: - Private

    private static func emptyWindow(
        pendingUntil: Date?,
        truncatedAtRideStart: Bool
    ) -> PinWindow {
        PinWindow(
            segmentIds: [],
            inOffset: 0,
            outOffset: 0,
            pendingUntil: pendingUntil,
            hasGap: false,
            truncatedAtRideStart: truncatedAtRideStart
        )
    }
}
