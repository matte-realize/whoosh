import Foundation

/// Device-local feature settings for crash alerts (spec design "Entities").
/// Stored in `UserDefaults` — **no contact data** lives here (that is Keychain
/// only). Off by default (Requirement 1.4).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
/// - `enabled`: master toggle for the feature.
/// - `riderLabel`: first name or nickname used in messages (≤ 20 chars,
///   restricted charset); alerts cannot be enabled without it (Requirement 2.9).
/// - `countdownSeconds`: optional rider override, clamped by `CrashResponseTuning`.
/// - `developerToolsEnabled`: gates the "Simulate crash" demo path.
/// - `freshInstallMarker`: app-container marker used to purge orphaned Keychain
///   contacts on a fresh install (Requirement 2.8).
struct CrashAlertSettings: Equatable, Codable, Sendable {
    var enabled: Bool
    var riderLabel: String?
    var countdownSeconds: TimeInterval?
    var developerToolsEnabled: Bool
    var freshInstallMarker: Bool

    init(
        enabled: Bool = true,
        riderLabel: String? = nil,
        countdownSeconds: TimeInterval? = nil,
        developerToolsEnabled: Bool = false,
        freshInstallMarker: Bool = false
    ) {
        self.enabled = enabled
        self.riderLabel = riderLabel
        self.countdownSeconds = countdownSeconds
        self.developerToolsEnabled = developerToolsEnabled
        self.freshInstallMarker = freshInstallMarker
    }
}
