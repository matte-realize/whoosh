import Foundation

/// Codable wire DTOs for the crash-alert Edge Functions (contract §5.2/§5.5).
/// These are the on-the-wire JSON shapes; the notifier maps the app's domain
/// `CrashNotificationRequest`/`CrashNotificationResult` to and from them. Kept
/// in `Services/Notification` with the notifier — they encode the exact field
/// names and conventions the backend agreed to.
///
/// Privacy invariant (contract §1.2, privacy steering): the request shape has
/// **no field that can carry footage, media, or arbitrary free text**. The only
/// free text is `riderLabel`, already charset-restricted by the sanitizer. There
/// is deliberately no clip/URL/body field here.
nonisolated enum CrashAlertWire {
    /// Current schema/template integers (contract §4). Breaking changes bump them.
    static let schemaVersion = 1

    // MARK: - Request (§5.2)

    struct Request: Encodable, Sendable {
        let schemaVersion: Int
        let templateVersion: Int
        let crashEventId: String
        let kind: String
        let riderLabel: String
        let detectedAt: String
        let utcOffsetMinutes: Int
        let delayedSeconds: Int
        /// Absent for `test`/`intro`/`all_clear`; present otherwise.
        let location: Location?
        let recipients: [Recipient]
        let consent: Consent
        let appVersion: String
    }

    struct Recipient: Encodable, Sendable {
        let recipientRef: String
        let e164: String
    }

    struct Consent: Encodable, Sendable {
        let version: Int
        /// ISO-8601 UTC acceptance time; absent when the app has no record.
        let acceptedAt: String?
    }

    /// The location block (§5.2/§A.1). `status` is one of `current`,
    /// `last_known`, `unavailable`. When `unavailable`, every coordinate field
    /// is **absent** (encoded as `nil`, dropped by the encoder below).
    struct Location: Encodable, Sendable {
        let status: String
        let latitude: Double?
        let longitude: Double?
        let accuracyMeters: Int?
        let ageSeconds: Int?
    }

    // MARK: - Response (§5.5)

    struct Response: Decodable, Sendable {
        let crashEventId: String
        let kind: String
        /// Absent on a `crash-alert-status` reply (§6); treated as `false`.
        let deduplicated: Bool?
        let recipients: [RecipientResult]
    }

    struct RecipientResult: Decodable, Sendable {
        let recipientRef: String
        let status: String
        let errorCode: String?
        let providerErrorCode: Int?
        let segments: Int?
        let updatedAt: String?
    }

    // MARK: - Error body (§5.3/§13)

    /// The backend's structured error body. `code` is the stable Whoosh error
    /// code; `retryable` is the contract's retry flag (used to override the
    /// status-derived default when present). PII-free by contract.
    struct ErrorBody: Decodable, Sendable {
        let code: String?
        let retryable: Bool?
    }
}
