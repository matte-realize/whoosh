import Foundation

/// Why a clip was pinned from the rolling ring buffer (rear-camera spec
/// Requirements 6.1, 6.6, 15.1; design "Entities"). A clip may carry more than
/// one reason, so `ClipRecord.reasons` is a set.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum ClipReason: String, Equatable, Codable, Sendable, CaseIterable {
    /// The rider explicitly saved a clip (phone, watch, or a shutter remote).
    case manual
    /// The experimental vehicle detector pinned the clip (off until measured
    /// thresholds exist; labelled "Vehicle detected (experimental)").
    case detection
    /// A probable crash pinned the clip via the crash-response footage buffer.
    case crash
    /// A demo-mode simulated detection pinned the clip (no bike needed).
    case demo
}
