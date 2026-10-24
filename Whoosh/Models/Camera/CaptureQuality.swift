import Foundation

/// The rider-visible recording quality choice in Settings / Mount & frame
/// (rear-camera spec Requirement 18.1, design "Mount & frame: Choices →
/// Profile (Standard / Efficient)"). Maps to a `CaptureProfile`; the `Reduced`
/// profile is a thermal/battery step the policies apply automatically and is
/// not a rider choice, so it is deliberately absent here.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum CaptureQuality: String, Equatable, Codable, Sendable, CaseIterable {
    /// 1080p30 — the default for demo clarity (O-CAM3).
    case standard
    /// 720p30 — lighter on battery/heat/storage; the Low Power Mode default.
    case efficient

    /// A short display name for Settings.
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .efficient: return "Efficient"
        }
    }

    /// The capture profile this quality requests (before thermal/battery steps).
    var profile: CaptureProfile {
        switch self {
        case .standard: return .standard
        case .efficient: return .efficient
        }
    }
}
