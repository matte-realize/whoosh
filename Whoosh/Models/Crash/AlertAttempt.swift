import Foundation

/// Per-recipient delivery status (spec Requirement 11.2, contract section 5.6).
/// Statuses never regress and terminal statuses are sticky; `rank` encodes the
/// ordering `queued < sent < {delivered, undelivered, failed, rejected}`.
///
/// Foundation-only enum; `Codable`, `Sendable`, `CaseIterable`. Raw values match
/// the backend contract.
enum AttemptStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case sent
    case delivered
    case undelivered
    case failed
    case rejected

    /// Monotonic ordering rank (Requirement 11.8).
    var rank: Int {
        switch self {
        case .queued: return 0
        case .sent: return 1
        case .delivered, .undelivered, .failed, .rejected: return 2
        }
    }

    /// Terminal statuses do not transition further.
    var isTerminal: Bool {
        switch self {
        case .delivered, .undelivered, .failed, .rejected: return true
        case .queued, .sent: return false
        }
    }
}

/// One per-recipient send attempt within a `CrashAlertRecord` (spec Requirement
/// 11.2). Stores the contact reference, a label snapshot, and the **masked
/// number (last 2 digits only)** — never the full phone number (Requirement
/// 11.3).
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct AlertAttempt: Equatable, Codable, Sendable, Identifiable {
    var id: UUID
    let recipientRef: UUID
    let labelSnapshot: String
    /// Last two digits of the recipient's number, for audit display only.
    let maskedNumber: String
    let kind: CrashMessageKind
    var status: AttemptStatus
    var whooshErrorCode: String?
    var providerErrorCode: Int?
    let attemptedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        recipientRef: UUID,
        labelSnapshot: String,
        maskedNumber: String,
        kind: CrashMessageKind,
        status: AttemptStatus,
        whooshErrorCode: String? = nil,
        providerErrorCode: Int? = nil,
        attemptedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.recipientRef = recipientRef
        self.labelSnapshot = labelSnapshot
        self.maskedNumber = maskedNumber
        self.kind = kind
        self.status = status
        self.whooshErrorCode = whooshErrorCode
        self.providerErrorCode = providerErrorCode
        self.attemptedAt = attemptedAt
        self.updatedAt = updatedAt
    }
}
