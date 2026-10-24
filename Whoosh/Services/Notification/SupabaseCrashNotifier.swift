import Foundation

/// The opt-in Supabase implementation of `CrashNotifier` (crash-response
/// task 25). Mirrors `SupabaseRideSyncService`: an `actor` so all network work
/// runs **off the main actor**, owning the *policy* (DTO encode/decode, error
/// classification per the contract's client-behaviour table §13) while the wire
/// call goes through an injected `CrashNotifierTransport`. The only type that
/// imports the Supabase SDK is `SupabaseFunctionsCrashTransport`, so every unit
/// test injects a transport double and never touches the network.
///
/// Lives in `Services/Notification`, the only crash folder allowed to touch the
/// network (privacy steering). The request shape (`CrashAlertWire.Request`)
/// carries no footage, media, or free text beyond the sanitized `riderLabel`.
///
/// Behaviour:
/// - `send` encodes the request, pre-warms the session, `POST`s
///   `send-crash-alert` (10 s client timeout, contract §4), decodes the
///   per-recipient results, and on a non-2xx maps the `{ code, retryable }`
///   body to a typed `CrashNotifierError`. A `401` refreshes the session once
///   and retries (§13). A transport/offline error becomes `.noConnection`;
///   a timeout becomes `.timeout` (unknown outcome).
/// - `status` `GET`s `crash-alert-status?crashEventId=…&kind=…` and decodes the
///   same per-recipient shape.
actor SupabaseCrashNotifier: CrashNotifier {
    private let transport: CrashNotifierTransport
    private let appVersion: String

    /// The client-side timeout (contract §4: function replies within 8 s, client
    /// timeout 10 s).
    private let clientTimeout: TimeInterval = 10

    private static let sendFunction = "send-crash-alert"
    private static let statusFunction = "crash-alert-status"

    init(
        transport: CrashNotifierTransport,
        appVersion: String
    ) {
        self.transport = transport
        self.appVersion = appVersion
    }

    // MARK: - CrashNotifier

    func send(_ request: CrashNotificationRequest) async throws -> CrashNotificationResult {
        let body = try encodeSendBody(request)
        let data = try await postRefreshingOnce(
            function: Self.sendFunction,
            body: body
        )
        return try decodeResult(data, fallbackKind: request.kind)
    }

    func status(crashEventId: UUID, kind: CrashMessageKind) async throws -> CrashNotificationResult {
        let query = [
            URLQueryItem(name: "crashEventId", value: crashEventId.uuidString.lowercased()),
            URLQueryItem(name: "kind", value: kind.rawValue),
        ]
        let data = try await getRefreshingOnce(
            function: Self.statusFunction,
            query: query
        )
        return try decodeResult(data, fallbackKind: kind)
    }

    // MARK: - Transport with one auth refresh (§13)

    private func postRefreshingOnce(function: String, body: Data) async throws -> Data {
        do {
            try await transport.ensureSession()
            return try await transport.post(functionName: function, body: body, timeout: clientTimeout)
        } catch let error as CrashTransportError {
            if error.statusCode == 401 {
                // Refresh the anonymous session once and retry (§13 `401`).
                try await transport.ensureSession()
                do {
                    return try await transport.post(functionName: function, body: body, timeout: clientTimeout)
                } catch let retryError as CrashTransportError {
                    throw Self.map(retryError)
                }
            }
            throw Self.map(error)
        }
    }

    private func getRefreshingOnce(function: String, query: [URLQueryItem]) async throws -> Data {
        do {
            try await transport.ensureSession()
            return try await transport.get(functionName: function, query: query, timeout: clientTimeout)
        } catch let error as CrashTransportError {
            if error.statusCode == 401 {
                try await transport.ensureSession()
                do {
                    return try await transport.get(functionName: function, query: query, timeout: clientTimeout)
                } catch let retryError as CrashTransportError {
                    throw Self.map(retryError)
                }
            }
            throw Self.map(error)
        }
    }

    // MARK: - Encoding (§5.2)

    private func encodeSendBody(_ request: CrashNotificationRequest) throws -> Data {
        let wire = CrashAlertWire.Request(
            schemaVersion: CrashAlertWire.schemaVersion,
            templateVersion: request.templateVersion,
            crashEventId: request.crashEventId.uuidString.lowercased(),
            kind: request.kind.rawValue,
            riderLabel: request.riderLabel,
            detectedAt: Self.isoString(request.detectedAt),
            utcOffsetMinutes: request.utcOffsetMinutes,
            delayedSeconds: request.delayedSeconds,
            location: Self.locationDTO(for: request),
            recipients: request.recipients.map {
                CrashAlertWire.Recipient(
                    recipientRef: $0.recipientRef.uuidString.lowercased(),
                    e164: $0.e164
                )
            },
            consent: CrashAlertWire.Consent(
                version: request.consentVersion,
                acceptedAt: nil
            ),
            appVersion: appVersion
        )
        let encoder = JSONEncoder()
        // Stable key order aids request-shape tests; `nil`s are dropped so an
        // `unavailable` location omits coordinate fields (§5.2).
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    /// Build the location DTO per §5.2/§A.1, or `nil` when the message kind
    /// carries no location (`test`/`intro`/`all_clear`).
    private nonisolated static func locationDTO(for request: CrashNotificationRequest) -> CrashAlertWire.Location? {
        switch request.kind {
        case .test, .intro, .allClear:
            return nil
        case .crashAlert, .drill:
            break
        }
        guard let snapshot = request.location else {
            return CrashAlertWire.Location(
                status: LocationFixStatus.unavailable.rawValue,
                latitude: nil, longitude: nil, accuracyMeters: nil, ageSeconds: nil
            )
        }
        switch snapshot.status {
        case .unavailable:
            return CrashAlertWire.Location(
                status: LocationFixStatus.unavailable.rawValue,
                latitude: nil, longitude: nil, accuracyMeters: nil, ageSeconds: nil
            )
        case .current, .lastKnown:
            // Precise, not privacy-zone trimmed (Requirement 16.5). Coordinates
            // to 5 decimals; accuracy rounded, min 1; age floored (§A.1).
            let lat = snapshot.latitude.map { round5($0) }
            let lon = snapshot.longitude.map { round5($0) }
            let accuracy = snapshot.horizontalAccuracy.map { max(1, Int($0.rounded())) }
            let age = snapshot.fixTime.map { max(0, Int(request.detectedAt.timeIntervalSince($0))) }
            return CrashAlertWire.Location(
                status: snapshot.status.rawValue,
                latitude: lat,
                longitude: lon,
                accuracyMeters: accuracy,
                ageSeconds: age
            )
        }
    }

    private nonisolated static func round5(_ value: Double) -> Double {
        (value * 100_000).rounded() / 100_000
    }

    // MARK: - Decoding (§5.5)

    private func decodeResult(_ data: Data, fallbackKind: CrashMessageKind) throws -> CrashNotificationResult {
        let decoder = JSONDecoder()
        guard let wire = try? decoder.decode(CrashAlertWire.Response.self, from: data) else {
            // A 2xx we can't parse is an unknown outcome (retry once, §13).
            throw CrashNotifierError(.unknown)
        }
        let kind = CrashMessageKind(rawValue: wire.kind) ?? fallbackKind
        let eventId = UUID(uuidString: wire.crashEventId) ?? UUID()
        let now = Date()
        let recipients: [CrashRecipientResult] = wire.recipients.compactMap { r in
            guard
                let ref = UUID(uuidString: r.recipientRef),
                let status = AttemptStatus(rawValue: r.status)
            else { return nil }
            let updatedAt = r.updatedAt.flatMap { Self.isoDate($0) } ?? now
            return CrashRecipientResult(
                recipientRef: ref,
                status: status,
                whooshErrorCode: r.errorCode,
                providerErrorCode: r.providerErrorCode,
                segments: r.segments ?? 0,
                updatedAt: updatedAt
            )
        }
        return CrashNotificationResult(
            crashEventId: eventId,
            kind: kind,
            deduplicated: wire.deduplicated ?? false,
            recipients: recipients
        )
    }

    // MARK: - Error mapping (§5.3/§13)

    /// Map a transport failure to a typed `CrashNotifierError`. Prefers the
    /// backend's structured `{ code, retryable }` body; falls back to the HTTP
    /// status when the body is absent/unparseable.
    private nonisolated static func map(_ error: CrashTransportError) -> CrashNotifierError {
        if error.isTimeout {
            return CrashNotifierError(.timeout)
        }
        guard let status = error.statusCode else {
            // No response ⇒ transport/offline; retryable with the same id (§13).
            return CrashNotifierError(.noConnection)
        }

        let parsed = error.body.flatMap { try? JSONDecoder().decode(CrashAlertWire.ErrorBody.self, from: $0) }
        if let codeString = parsed?.code, let code = CrashNotifierErrorCode(rawValue: codeString) {
            if let retryable = parsed?.retryable {
                return CrashNotifierError(code: code, isRetryable: retryable)
            }
            return CrashNotifierError(code)
        }

        // No usable body code: classify from the HTTP status (§13 table).
        return CrashNotifierError(codeForStatus(status))
    }

    /// The default error code for an HTTP status when no body code is present.
    private nonisolated static func codeForStatus(_ status: Int) -> CrashNotifierErrorCode {
        switch status {
        case 401: return .unauthenticated
        case 403: return .clientUpgradeRequired
        case 409: return .idempotencyConflict
        case 413: return .payloadTooLarge
        case 422: return .invalidRequest
        case 429: return .rateLimited
        case 503: return .serviceDisabled
        case 400: return .invalidRequest
        case 500, 502, 504: return .serverError
        default:
            // Unknown 4xx is non-retryable-ish but treated as unknown (retry
            // once, §13); unknown 5xx is a server error (retryable).
            return (500...599).contains(status) ? .serverError : .unknown
        }
    }

    // MARK: - Date formatting (§4: ISO-8601 UTC with `Z`)

    /// A fresh UTC ISO-8601 formatter. `ISO8601DateFormatter` is not `Sendable`,
    /// so a shared static instance can't cross actors; building one per call is
    /// cheap for the handful of crash-alert requests and keeps the type
    /// concurrency-clean.
    private nonisolated static func makeISO8601() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    private nonisolated static func isoString(_ date: Date) -> String {
        makeISO8601().string(from: date)
    }

    private nonisolated static func isoDate(_ string: String) -> Date? {
        makeISO8601().date(from: string)
    }
}
