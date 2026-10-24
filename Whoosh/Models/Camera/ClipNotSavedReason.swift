import Foundation

/// Why a clip save did not produce a clip (rear-camera spec Requirement 6.6,
/// design "Pinning and ClipWindowPolicy" / routing table). Spoken or shown as a
/// calm, honest notice — a save can fail and the rider is told.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum ClipNotSavedReason: String, Equatable, Codable, Sendable, CaseIterable {
    /// No segments exist in the requested window ("nothing to save").
    case nothingToSave = "nothing_to_save"
    /// The pinned-clip storage cap leaves no room for a new clip.
    case storageFull = "storage_full"
    /// The camera was not recording when the save was requested.
    case notRecording = "not_recording"
}
