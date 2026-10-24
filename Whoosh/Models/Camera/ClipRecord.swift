import Foundation

/// A saved clip pinned from the ring buffer (rear-camera spec Requirement 6/8,
/// design "Entities"). The persisted shape lives in a separate `ClipRepository`
/// (SwiftData `ClipRecordEntity`), so the shipped `RideRecord` model never
/// migrates; this value type is the domain representation used by the pure
/// pinning policies and the UI.
///
/// Footage is on-device only: a `ClipRecord` references local paths and a local
/// `eventRef`, and is never uploaded, linked, or put in a message.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`, `Identifiable`.
struct ClipRecord: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    let rideId: UUID
    /// Why the clip was pinned (may be more than one reason after coalescing).
    var reasons: Set<ClipReason>
    let createdAt: Date
    /// Wall-clock start of the kept footage (snapped to a segment boundary).
    let start: Date
    /// Wall-clock end of the kept footage.
    let end: Date
    /// Playback in-point offset in seconds from `start`.
    let inOffset: TimeInterval
    /// Playback out-point offset in seconds from `start`.
    let outOffset: TimeInterval
    /// Clip duration in seconds (out − in).
    let durationSeconds: TimeInterval
    /// Bytes on disk (linked segments).
    let bytes: Int64
    /// Local thumbnail path, or `nil` until generated.
    var thumbnailPath: String?
    /// Whether the clip has an audio track.
    let hasAudio: Bool
    /// Lifecycle state (`pending`/`saved`/`endedEarly`).
    var state: ClipState
    /// Whether the clip spans a recording gap (interruption inside the window).
    let hasGap: Bool
    /// A local-only event reference (near-miss id or crash-event id). Never
    /// leaves the device.
    var eventRef: String?
    /// When the clip auto-deletes under retention (default 30 days; O-CAM4).
    var expiresAt: Date

    init(
        id: UUID,
        rideId: UUID,
        reasons: Set<ClipReason>,
        createdAt: Date,
        start: Date,
        end: Date,
        inOffset: TimeInterval,
        outOffset: TimeInterval,
        durationSeconds: TimeInterval,
        bytes: Int64,
        thumbnailPath: String?,
        hasAudio: Bool,
        state: ClipState,
        hasGap: Bool,
        eventRef: String?,
        expiresAt: Date
    ) {
        self.id = id
        self.rideId = rideId
        self.reasons = reasons
        self.createdAt = createdAt
        self.start = start
        self.end = end
        self.inOffset = inOffset
        self.outOffset = outOffset
        self.durationSeconds = durationSeconds
        self.bytes = bytes
        self.thumbnailPath = thumbnailPath
        self.hasAudio = hasAudio
        self.state = state
        self.hasGap = hasGap
        self.eventRef = eventRef
        self.expiresAt = expiresAt
    }

    /// Whether the clip has reached or passed its retention expiry at `now`.
    func isExpired(at now: Date) -> Bool { now >= expiresAt }
}
