import Foundation

/// The verification state of an emergency contact (spec Requirement 2.5).
/// Automatic alerts are sent only to contacts in `reachable` state.
enum ContactVerification: String, Codable, Sendable, CaseIterable {
    /// No message has been sent to this contact yet.
    case unverified
    /// An introduction message has been sent but not yet confirmed.
    case introSent
    /// The provider reported `sent` or `delivered` for an intro/test.
    case reachable
    /// The provider reported undelivered/failed with an unreachable-class code.
    case undeliverable
    /// The recipient replied STOP.
    case optedOut
}

/// A trusted emergency contact chosen by the rider. Stored **on the device
/// only**, in the Keychain (spec Requirement 2.7); never in SwiftData,
/// UserDefaults, logs, or iCloud.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable` so the store
/// can encode a list of contacts into a single Keychain blob and tests can
/// construct fixtures cheaply. Numbers are stored in E.164 (US/CA, NANP) form.
struct EmergencyContact: Equatable, Codable, Sendable, Identifiable {
    let id: UUID
    var label: String
    var e164: String
    var verification: ContactVerification
    var lastStatusAt: Date?

    init(
        id: UUID,
        label: String,
        e164: String,
        verification: ContactVerification = .unverified,
        lastStatusAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.e164 = e164
        self.verification = verification
        self.lastStatusAt = lastStatusAt
    }

    /// Changing the number resets verification to `unverified` (Requirement 2.6).
    func changingNumber(to newE164: String) -> EmergencyContact {
        EmergencyContact(
            id: id,
            label: label,
            e164: newE164,
            verification: .unverified,
            lastStatusAt: nil
        )
    }

    /// Changing only the label preserves the verification state.
    func changingLabel(to newLabel: String) -> EmergencyContact {
        EmergencyContact(
            id: id,
            label: newLabel,
            e164: e164,
            verification: verification,
            lastStatusAt: lastStatusAt
        )
    }
}
