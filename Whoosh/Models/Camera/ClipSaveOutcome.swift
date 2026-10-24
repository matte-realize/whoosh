import Foundation

/// The outcome of a manual "save clip" action (rear-camera spec Requirement
/// 6.7, 13.2; design "Eyes-free surfaces: Commands"). Surfaced to the rider as a
/// short confirmation or a calm "nothing to save" notice — a save is never
/// silently lost.
///
/// Foundation-only enum; `Equatable`, `Codable`, `Sendable`.
enum ClipSaveOutcome: Equatable, Codable, Sendable {
    /// A clip was saved (its post-roll may still be pending).
    case saved
    /// The save is pending a debounce / post-roll but was accepted.
    case pending
    /// Nothing to save for the given reason (e.g. not recording, no segments).
    case nothingToSave
}
