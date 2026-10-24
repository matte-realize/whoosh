import Foundation

/// The kind of crash-alert message (spec Requirement 10, contract section 5.1).
/// Named `CrashMessageKind` to avoid clashing with the existing `AlertKind` in
/// `Services/Alerts`. Raw values match the backend contract's `kind` field.
///
/// Foundation-only enum; `Codable`, `Sendable`, `CaseIterable`.
enum CrashMessageKind: String, Codable, Sendable, CaseIterable {
    /// Countdown expired / Send now / recovery send — the real alert.
    case crashAlert = "crash_alert"
    /// The "Simulate crash" demo path; begins "WHOOSH DEMO - NOT REAL".
    case drill
    /// Rider taps "Send a test"; states clearly that no crash happened.
    case test
    /// New-contact introduction.
    case intro
    /// Rider taps "Tell contacts I'm OK" (stretch).
    case allClear = "all_clear"
}
