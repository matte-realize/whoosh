import Foundation

/// Abstraction over the rider's crash-alert consent record (spec Requirement
/// 3.1, 3.6, 3.7). Separate from ride-sync consent; enabling one never enables
/// the other.
///
/// The record is versioned: a material message-text change bumps the version
/// (`CrashResponseTuning`/caller supplies it) and disables automatic alerts
/// until re-accepted, which `CrashArming` enforces via `isCurrent(minimumVersion:)`.
/// Stored device-locally (UserDefaults JSON); it carries **no contact data**
/// (Requirement 16; design "Entities").
///
/// `UserDefaultsConsentStore` is the shipping implementation;
/// `InMemoryConsentStore` backs unit tests and previews. Runs on the main actor,
/// consistent with the other stores.
@MainActor
protocol ConsentStore {
    /// The current consent record, or `nil` if the rider has never consented
    /// (or has revoked, which clears it).
    func current() -> ConsentRecord?

    /// Record consent at the given version and acknowledgement, stamped with
    /// `acceptedAt`. Replaces any previous record (Requirement 3.1, 3.6).
    func record(version: Int, acknowledgedNotGuaranteed: Bool, acceptedAt: Date)

    /// Revoke consent: clears the stored record so automatic alerts are
    /// disabled immediately (Requirement 3.7).
    func revoke()
}
