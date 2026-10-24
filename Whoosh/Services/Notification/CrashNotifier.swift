import Foundation

/// A single recipient of a crash-alert send, identified by the client-generated
/// contact UUID and the E.164 number (spec contract §5.2). The number is passed
/// to the notifier only at send time and is never persisted in a crash record.
///
/// Foundation-only value type; `Equatable`, `Sendable`.
nonisolated struct CrashNotificationRecipient: Equatable, Sendable {
    let recipientRef: UUID
    let e164: String

    init(recipientRef: UUID, e164: String) {
        self.recipientRef = recipientRef
        self.e164 = e164
    }
}

/// The structured request to send a crash-alert message (spec contract §5.2).
/// The backend renders a **fixed template** from these fields; there is
/// deliberately **no field that can carry footage, media, or arbitrary free
/// text** (Requirement 9.2, privacy steering). `riderLabel` is the only free
/// text and is charset-restricted by the sanitizer before it reaches here.
///
/// Foundation-only value type; `Equatable`, `Sendable`.
nonisolated struct CrashNotificationRequest: Equatable, Sendable {
    let crashEventId: UUID
    let kind: CrashMessageKind
    let riderLabel: String
    let detectedAt: Date
    let utcOffsetMinutes: Int
    let delayedSeconds: Int
    /// The location snapshot for the message. Absent for `test`/`intro`/
    /// `all_clear`; present (current/last-known/unavailable) otherwise.
    let location: LocationSnapshot?
    let recipients: [CrashNotificationRecipient]
    let consentVersion: Int
    let templateVersion: Int

    init(
        crashEventId: UUID,
        kind: CrashMessageKind,
        riderLabel: String,
        detectedAt: Date,
        utcOffsetMinutes: Int,
        delayedSeconds: Int,
        location: LocationSnapshot?,
        recipients: [CrashNotificationRecipient],
        consentVersion: Int,
        templateVersion: Int
    ) {
        self.crashEventId = crashEventId
        self.kind = kind
        self.riderLabel = riderLabel
        self.detectedAt = detectedAt
        self.utcOffsetMinutes = utcOffsetMinutes
        self.delayedSeconds = delayedSeconds
        self.location = location
        self.recipients = recipients
        self.consentVersion = consentVersion
        self.templateVersion = templateVersion
    }
}

/// A per-recipient outcome returned from a send or status query (spec contract
/// §5.5/§5.6). Carries the recipient reference, the current `AttemptStatus`, an
/// optional Whoosh/provider error code, and the SMS segment count.
///
/// Foundation-only value type; `Equatable`, `Sendable`.
nonisolated struct CrashRecipientResult: Equatable, Sendable {
    let recipientRef: UUID
    let status: AttemptStatus
    let whooshErrorCode: String?
    let providerErrorCode: Int?
    let segments: Int
    let updatedAt: Date

    init(
        recipientRef: UUID,
        status: AttemptStatus,
        whooshErrorCode: String? = nil,
        providerErrorCode: Int? = nil,
        segments: Int,
        updatedAt: Date
    ) {
        self.recipientRef = recipientRef
        self.status = status
        self.whooshErrorCode = whooshErrorCode
        self.providerErrorCode = providerErrorCode
        self.segments = segments
        self.updatedAt = updatedAt
    }
}

/// The result of a `send`/`status` call: the per-recipient results plus whether
/// the whole request was deduplicated (every recipient already sent).
///
/// Foundation-only value type; `Equatable`, `Sendable`.
nonisolated struct CrashNotificationResult: Equatable, Sendable {
    let crashEventId: UUID
    let kind: CrashMessageKind
    let deduplicated: Bool
    let recipients: [CrashRecipientResult]

    init(
        crashEventId: UUID,
        kind: CrashMessageKind,
        deduplicated: Bool,
        recipients: [CrashRecipientResult]
    ) {
        self.crashEventId = crashEventId
        self.kind = kind
        self.deduplicated = deduplicated
        self.recipients = recipients
    }
}

/// A request-level error from the crash-alert backend, classified `retryable`
/// or `nonRetryable` with the Whoosh error code from the contract's
/// client-behaviour table (spec contract §13). The coordinator uses `isRetryable`
/// to decide between a backoff retry (same `crashEventId`) and an immediate
/// composer fallback.
///
/// Foundation-only; `Equatable`, `Sendable`, `Error`.
struct CrashNotifierError: Error, Equatable, Sendable {
    /// The stable Whoosh error code (from `CrashNotifierErrorCode`).
    let code: CrashNotifierErrorCode
    /// Whether the coordinator may retry with the same `crashEventId`.
    let isRetryable: Bool

    init(code: CrashNotifierErrorCode, isRetryable: Bool) {
        self.code = code
        self.isRetryable = isRetryable
    }

    /// Build an error using the code's default retryability.
    init(_ code: CrashNotifierErrorCode) {
        self.code = code
        self.isRetryable = code.isRetryableByDefault
    }
}

/// Stable Whoosh request-level error codes (spec contract §5.3/§13). These are
/// the codes the client acts on; per-recipient provider codes live on
/// `CrashRecipientResult`.
///
/// Foundation-only enum; `String`-backed, `Codable`, `Sendable`, `CaseIterable`.
enum CrashNotifierErrorCode: String, Codable, Sendable, CaseIterable {
    // Non-retryable client/validation (contract §5.3, §13)
    case clientUpgradeRequired = "client_upgrade_required"
    case unsupportedTemplateVersion = "unsupported_template_version"
    case invalidRequest = "invalid_request"
    case invalidLabel = "invalid_label"
    case eventTooOld = "event_too_old"
    case invalidLocation = "invalid_location"
    case tooManyRecipients = "too_many_recipients"
    case invalidRecipient = "invalid_recipient"
    case payloadTooLarge = "payload_too_large"
    case idempotencyConflict = "idempotency_conflict"
    case rateLimited = "rate_limited"
    case serviceDisabled = "service_disabled"

    // Retryable transport/server (contract §13)
    case unauthenticated = "unauthenticated"
    case serverError = "server_error"
    case timeout = "timeout"
    case noConnection = "no_connection"
    case unknown = "unknown"

    /// The default classification from the contract's client-behaviour table.
    /// `unauthenticated` is retryable (refresh the session once); `unknown` is
    /// retried once by the coordinator.
    nonisolated var isRetryableByDefault: Bool {
        switch self {
        case .unauthenticated, .serverError, .timeout, .noConnection, .unknown:
            return true
        case .clientUpgradeRequired, .unsupportedTemplateVersion, .invalidRequest,
             .invalidLabel, .eventTooOld, .invalidLocation, .tooManyRecipients,
             .invalidRecipient, .payloadTooLarge, .idempotencyConflict,
             .rateLimited, .serviceDisabled:
            return false
        }
    }
}

/// Sends crash-alert messages through the backend and reports delivery status
/// (spec Requirement 9, design "Service protocols"). v1 Tier 0 ships
/// `NoopCrashNotifier`; `FakeCrashNotifier` backs the tests; `SupabaseCrashNotifier`
/// (a later, blocked Tier 1 task) is the only crash code that touches the
/// network and lives under `Services/Notification/`.
///
/// ## Contract
/// - **Fixed templates, no free text.** `CrashNotificationRequest` has no field
///   that can carry footage, media, or arbitrary text; the backend renders from
///   structured fields only (Requirement 9.2).
/// - **Idempotent.** A repeated `send` with the same (`crashEventId`, `kind`)
///   never sends a second message to the same recipient; the result carries
///   `deduplicated` when every recipient was already sent (contract §13).
/// - **Typed errors.** A request-level failure throws `CrashNotifierError` with
///   a stable code and a `isRetryable` flag; per-recipient failures are reported
///   as `CrashRecipientResult`s with status `rejected`/`failed` and a code.
/// - **Off the main actor.** The real implementation runs network work off the
///   main actor; the protocol is actor-agnostic. `async` methods return results
///   the main-actor coordinator consumes.
protocol CrashNotifier: Sendable {
    /// Send the crash-alert message. Throws `CrashNotifierError` on a
    /// request-level failure; otherwise returns per-recipient results.
    func send(_ request: CrashNotificationRequest) async throws -> CrashNotificationResult

    /// Fetch the current per-recipient statuses for an event. Throws
    /// `CrashNotifierError` on a request-level failure.
    func status(crashEventId: UUID, kind: CrashMessageKind) async throws -> CrashNotificationResult
}
