import Foundation

/// Orchestrates pinning a clip from the rolling ring buffer (rear-camera spec
/// task 16; Requirements 6.1–6.9, 8.4, 8.5, 8.7). Pure policy decisions come
/// from `ClipWindowPolicy` and `ClipCoalescing`; this type wires them to the
/// `SegmentStore` (hard-link the kept segments), the `ClipRepository` (persist
/// the record), and a `ClipThumbnailing` (a thumbnail once the clip is saved).
///
/// ## Behaviour (design "Pinning and ClipWindowPolicy")
/// - **Manual save** is debounced by `tuning.manualSaveDebounce`: a second save
///   inside the window is ignored (returns `.debounced`).
/// - **Window** comes from `ClipWindowPolicy` using the per-reason pre/post. No
///   overlapping segments ⇒ `.notSaved(.nothingToSave)`.
/// - **Coalescing** merges a new window into an overlapping / near-adjacent
///   existing clip (up to the max clip duration), keeping every reason.
/// - **Storage cap**: a manual save is allowed while any room remains under the
///   pinned cap; auto-pins (detection/crash/demo) need the whole estimate to
///   fit, else `.notSaved(.storageFull)`.
/// - **Pending post-roll**: if the post-roll is still in the future the clip is
///   written `pending`; `finalizePending` later flips it to `saved` (or
///   `endedEarly` at ride end). The thumbnail is generated once the clip is
///   `saved`/`endedEarly`.
/// - A camera/clip failure never changes ride state or GPS points; a thumbnail
///   failure never blocks saving the clip.
///
/// `@MainActor` to match the stores; the pin itself is small metadata work plus
/// an awaited thumbnail. It never touches the capture queue.
@MainActor
final class ClipPinner {
    /// The outcome of a pin request.
    enum Result: Equatable, Sendable {
        /// A clip was saved (post-roll already complete). Carries the clip id.
        case saved(UUID)
        /// A clip was created but its post-roll is still pending. Carries the id.
        case pending(UUID)
        /// A new window merged into an existing clip. Carries the clip id.
        case merged(UUID)
        /// A manual save was ignored because it was inside the debounce window.
        case debounced
        /// Nothing was saved, with the reason.
        case notSaved(ClipNotSavedReason)
    }

    private let segmentStore: SegmentStore
    private let clipRepository: ClipRepository
    private let thumbnailer: ClipThumbnailing
    private let layout: CameraStorageLayout
    private let tuning: RideCameraTuning
    private let clock: Clock

    /// The instant of the last accepted manual save, for debounce.
    private var lastManualSaveAt: Date?

    init(
        segmentStore: SegmentStore,
        clipRepository: ClipRepository,
        thumbnailer: ClipThumbnailing,
        layout: CameraStorageLayout,
        tuning: RideCameraTuning = RideCameraTuning(),
        clock: Clock
    ) {
        self.segmentStore = segmentStore
        self.clipRepository = clipRepository
        self.thumbnailer = thumbnailer
        self.layout = layout
        self.tuning = tuning
        self.clock = clock
    }

    // MARK: - Pinning

    /// Save a clip on an explicit rider action. Debounced; the window centres on
    /// `eventTime` (default: now), using the manual pre/post.
    @discardableResult
    func saveManually(
        rideId: UUID,
        rideStart: Date,
        eventTime: Date? = nil,
        eventRef: String? = nil
    ) async -> Result {
        let now = clock.now()
        if let last = lastManualSaveAt,
           now.timeIntervalSince(last) < tuning.manualSaveDebounce {
            return .debounced
        }
        lastManualSaveAt = now
        let request = PinRequest(reason: .manual, eventTime: eventTime ?? now, eventRef: eventRef)
        return await pin(request, rideId: rideId, rideStart: rideStart)
    }

    /// Pin a clip for any reason (manual/detection/crash/demo). Returns the
    /// outcome; never throws into the caller (storage failures become
    /// `.notSaved`).
    @discardableResult
    func pin(
        _ request: PinRequest,
        rideId: UUID,
        rideStart: Date
    ) async -> Result {
        let now = clock.now()
        let (pre, post) = tuning.pinPrePost(for: request.reason)
        let segments = segmentStore.segments(rideId: rideId)

        let window = ClipWindowPolicy.window(
            for: request,
            pre: pre,
            post: post,
            segments: segments,
            now: now,
            rideStart: rideStart
        )
        guard !window.isEmpty else {
            return .notSaved(.nothingToSave)
        }

        // Estimate the clip's bytes from the kept segments.
        let keptSegments = segments.filter { window.segmentIds.contains($0.id) }
        let estimatedBytes = keptSegments.reduce(Int64(0)) { $0 + $1.bytes }

        // Storage-cap check against the pinned cap and current usage.
        let usedByClips = (try? clipRepository.totalBytes()) ?? 0
        let freeUnderCap = max(0, tuning.pinnedMaxBytes - usedByClips)
        guard ClipCoalescing.allowsPin(
            reason: request.reason,
            estimatedBytes: estimatedBytes,
            freeBytesUnderCap: freeUnderCap
        ) else {
            return .notSaved(.storageFull)
        }

        // Coalescing: merge into an overlapping / near-adjacent existing clip?
        let existing = (try? clipRepository.clips(rideId: rideId)) ?? []
        let windowStart = keptSegments.first?.start ?? request.eventTime
        let windowEnd = keptSegments.last?.end ?? request.eventTime
        let decision = ClipCoalescing.coalesce(
            newStart: windowStart,
            newEnd: windowEnd,
            newReasons: [request.reason],
            existingClips: existing,
            coalesceGap: tuning.coalesceGap,
            maxClipDuration: tuning.maxClipDuration
        )

        switch decision {
        case let .merge(clipId, unionStart, unionEnd, reasons):
            return await mergeIntoClip(
                clipId: clipId,
                unionStart: unionStart,
                unionEnd: unionEnd,
                reasons: reasons,
                newSegments: keptSegments,
                window: window,
                rideId: rideId,
                request: request
            )
        case .new:
            return await createClip(
                keptSegments: keptSegments,
                window: window,
                rideId: rideId,
                request: request,
                now: now
            )
        }
    }

    // MARK: - Ride-end finalization

    /// Finalize any still-pending clips for the ride at ride end: a clip whose
    /// post-roll completed flips to `saved`; one that did not flips to
    /// `endedEarly`. A thumbnail is generated for each finalized clip.
    func finalizePending(rideId: UUID, now: Date? = nil) async {
        let instant = now ?? clock.now()
        let clips = (try? clipRepository.clips(rideId: rideId)) ?? []
        for var clip in clips where clip.state == .pending {
            clip.state = .saved // post-roll footage that exists is kept as saved
            // If the post-roll never arrived (ride ended before `end`), mark it
            // ended early so the UI is honest about the shorter clip.
            if clip.end > instant {
                clip.state = .endedEarly
            }
            try? clipRepository.save(clip)
            await attachThumbnailIfNeeded(&clip, rideId: rideId)
        }
    }

    // MARK: - Retention and cascade

    /// Delete every clip at or past its retention expiry (launch/foreground
    /// sweep). Removes the linked footage via the segment store, then the record.
    func sweepExpired(now: Date? = nil) {
        let instant = now ?? clock.now()
        let expired = (try? clipRepository.expired(now: instant)) ?? []
        for clip in expired {
            deleteClipFiles(clip)
            try? clipRepository.delete(id: clip.id)
        }
    }

    /// Delete one clip (its footage folder and the record).
    func deleteClip(id: UUID) {
        if let clip = try? clipRepository.clip(id: id) {
            deleteClipFiles(clip)
        }
        try? clipRepository.delete(id: id)
    }

    /// Cascade: delete every clip for a ride (ride deletion). Removes each clip's
    /// footage, then the records.
    func deleteClips(forRide rideId: UUID) {
        let clips = (try? clipRepository.clips(rideId: rideId)) ?? []
        for clip in clips { deleteClipFiles(clip) }
        try? clipRepository.deleteAll(rideId: rideId)
    }

    // MARK: - Private

    private func createClip(
        keptSegments: [SegmentInfo],
        window: PinWindow,
        rideId: UUID,
        request: PinRequest,
        now: Date
    ) async -> Result {
        let clipId = UUID()
        // Hard-link the kept segments into the clip folder (copy fallback in the
        // file store); this marks them pinned so the ring no longer evicts them.
        segmentStore.link(segmentIds: window.segmentIds, toClip: clipId)

        let start = keptSegments.first?.start ?? request.eventTime
        let end = keptSegments.last?.end ?? request.eventTime
        let bytes = keptSegments.reduce(Int64(0)) { $0 + $1.bytes }
        let isPending = window.pendingUntil != nil
        let state: ClipState = isPending ? .pending : .saved

        var clip = ClipRecord(
            id: clipId,
            rideId: rideId,
            reasons: [request.reason],
            createdAt: now,
            start: start,
            end: end,
            inOffset: window.inOffset,
            outOffset: window.outOffset,
            durationSeconds: max(0, window.outOffset - window.inOffset),
            bytes: bytes,
            thumbnailPath: nil,
            hasAudio: keptSegments.contains { $0.hasAudio },
            state: state,
            hasGap: window.hasGap,
            eventRef: request.eventRef,
            expiresAt: now.addingTimeInterval(tuning.clipRetention)
        )
        do {
            try clipRepository.save(clip)
        } catch {
            return .notSaved(.nothingToSave)
        }

        if isPending {
            return .pending(clipId)
        }
        await attachThumbnailIfNeeded(&clip, rideId: rideId)
        return .saved(clipId)
    }

    private func mergeIntoClip(
        clipId: UUID,
        unionStart: Date,
        unionEnd: Date,
        reasons: Set<ClipReason>,
        newSegments: [SegmentInfo],
        window: PinWindow,
        rideId: UUID,
        request: PinRequest
    ) async -> Result {
        guard let clip = try? clipRepository.clip(id: clipId) else {
            // The target vanished; fall back to a fresh clip.
            return await createClip(
                keptSegments: newSegments, window: window,
                rideId: rideId, request: request, now: clock.now()
            )
        }
        // Link any newly contributing segments into the existing clip folder (a
        // shared boundary segment is simply linked again — safe, idempotent).
        segmentStore.link(segmentIds: window.segmentIds, toClip: clipId)

        let mergedBytes = clip.bytes + newSegments.reduce(Int64(0)) { $0 + $1.bytes }

        let merged = ClipRecord(
            id: clip.id,
            rideId: clip.rideId,
            reasons: reasons,
            createdAt: clip.createdAt,
            start: unionStart,
            end: unionEnd,
            inOffset: clip.inOffset,
            outOffset: clip.outOffset + unionEnd.timeIntervalSince(clip.end),
            durationSeconds: unionEnd.timeIntervalSince(unionStart),
            bytes: mergedBytes,
            thumbnailPath: clip.thumbnailPath,
            hasAudio: clip.hasAudio || newSegments.contains { $0.hasAudio },
            state: window.pendingUntil != nil ? .pending : clip.state,
            hasGap: clip.hasGap || window.hasGap,
            eventRef: clip.eventRef ?? request.eventRef,
            expiresAt: clip.expiresAt
        )
        try? clipRepository.save(merged)
        return .merged(clipId)
    }

    /// Generate and attach a thumbnail if the clip does not have one yet. A
    /// failure is tolerated (the clip stays saved; the list shows a placeholder).
    private func attachThumbnailIfNeeded(_ clip: inout ClipRecord, rideId: UUID) async {
        guard clip.thumbnailPath == nil else { return }
        let sources = clipSegmentURLs(for: clip, rideId: rideId)
        guard !sources.isEmpty else { return }
        let destination = layout.thumbnailURL(clipId: clip.id)
        // Sample at the in-point (the event instant for a centred window).
        let generated = await thumbnailer.generateThumbnail(
            sourceURLs: sources,
            atOffset: clip.inOffset,
            destinationURL: destination
        )
        guard let generated else { return }
        clip.thumbnailPath = generated.path
        try? clipRepository.save(clip)
    }

    /// The ordered clip-folder segment file URLs for a clip (thumbnail source).
    private func clipSegmentURLs(for clip: ClipRecord, rideId: UUID) -> [URL] {
        // The segments are the pinned ones for the ride that fall inside the
        // clip's time range, ordered by index.
        segmentStore.segments(rideId: rideId)
            .filter { $0.isPinned && $0.end > clip.start && $0.start < clip.end }
            .sorted { $0.index < $1.index }
            .map { layout.clipSegmentURL($0, clipId: clip.id) }
    }

    private func deleteClipFiles(_ clip: ClipRecord) {
        // Remove the whole clip folder (linked segments + thumbnail).
        let dir = layout.clipDirectory(clipId: clip.id)
        try? FileManager.default.removeItem(at: dir)
    }
}
