import Foundation

/// The rider's recorded consent for crash alerts (spec Requirement 3).
///
/// Separate, explicit, and **versioned**: a material text change bumps the
/// version and disables automatic alerts until re-accepted. A separate
/// acknowledgement that Whoosh is not a guaranteed emergency-response service is
/// required before alerts can be enabled (Requirement 1.2).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`. Stored via
/// the `ConsentStore` (UserDefaults JSON); carries no contact data.
struct ConsentRecord: Equatable, Codable, Sendable {
    let version: Int
    let acceptedAt: Date
    let acknowledgedNotGuaranteed: Bool

    init(version: Int, acceptedAt: Date, acknowledgedNotGuaranteed: Bool) {
        self.version = version
        self.acceptedAt = acceptedAt
        self.acknowledgedNotGuaranteed = acknowledgedNotGuaranteed
    }

    /// Consent is current when it meets the minimum version and the rider
    /// acknowledged the not-a-guarantee statement.
    func isCurrent(minimumVersion: Int) -> Bool {
        acknowledgedNotGuaranteed && version >= minimumVersion
    }
}
