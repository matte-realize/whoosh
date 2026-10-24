import Foundation

/// The video codec used for a capture profile (rear-camera spec Requirement 3,
/// design "RideCameraTuning": HEVC with an H.264 fallback). Foundation-only so
/// the Models layer never imports AVFoundation.
///
/// `String`-backed `Codable`, `Equatable`, `Sendable`, `CaseIterable`.
enum VideoCodecKind: String, Equatable, Codable, Sendable, CaseIterable {
    /// HEVC (H.265) — the default; smaller files at equal quality.
    case hevc
    /// H.264 — the fallback when HEVC is unsupported (≈1.6× the bitrate).
    case h264
}
