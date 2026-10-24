import Foundation

/// Preserves pre-crash footage around a detected crash (spec Requirement 7.6,
/// design "Service protocols"). v1 ships only `NoopFootageBuffer` (returns no
/// reference); a real rolling buffer is a future task that exists only if camera
/// detection ships.
///
/// ## Contract (non-negotiable; see privacy steering)
/// - **Device-only.** Footage is preserved on the device and **never leaves it**
///   — never uploaded, never linked, never attached to a message. No crash-alert
///   request has any field that could carry footage.
/// - **Local reference only.** `preserve` returns an opaque local reference
///   string (e.g. a file-relative path/id) or `nil` ("no footage"); the crash
///   record stores only this reference, never the media itself in the message.
/// - **No capture session.** A footage buffer never opens a camera capture
///   session or requests camera permission; a real buffer may only use
///   asset-writer APIs over frames the detection pipeline already has.
/// - **Non-blocking.** `preserve` returns quickly and must never block or stop
///   ride recording.
/// - **Deletable.** `delete(reference:)` removes preserved footage; the rider
///   can delete it from the crash log.
protocol FootageBuffer: Sendable {
    /// Preserve footage around `detectedAt` for the given crash event. Returns
    /// a local-only reference, or `nil` when there is nothing to preserve. Never
    /// uploads or transmits anything.
    func preserve(eventId: UUID, around detectedAt: Date) -> String?

    /// Delete previously preserved footage by its local reference. Safe to call
    /// for an unknown reference.
    func delete(reference: String)
}
