import Foundation

/// The low-level network seam under `SupabaseCrashNotifier` (crash-response
/// task 25), mirroring the `RideSyncTransport` pattern used by sync.
///
/// Splitting the transport out from the notifier means the Supabase SDK lives in
/// exactly **one** type (`SupabaseFunctionsCrashTransport`) and every unit test
/// injects a fake transport — no test ever touches the network. The notifier
/// owns the *policy* (DTO encoding/decoding, error classification per the
/// contract's client-behaviour table); the transport owns only the wire call:
/// attach the anonymous Supabase session, `POST`/`GET` the Edge Function, and
/// hand back raw JSON bytes (or throw a `CrashTransportError`).
///
/// All methods run off the main actor (the Supabase implementation is an
/// `actor`). Lives in `Services/Notification`, the only crash folder allowed to
/// touch the network (privacy steering).
protocol CrashNotifierTransport: Sendable {
    /// Ensure there is a valid anonymous session (sign in or refresh). Called
    /// before the first request and again after a `401`.
    func ensureSession() async throws

    /// `POST` a JSON body to an Edge Function and return the raw response bytes.
    /// A non-2xx response is thrown as a `CrashTransportError` carrying the
    /// status code and the (PII-free) error body so the notifier can classify
    /// it; a transport/offline error is thrown with `statusCode == nil`.
    func post(functionName: String, body: Data, timeout: TimeInterval) async throws -> Data

    /// `GET` an Edge Function with query items and return the raw response
    /// bytes. Same error contract as `post`.
    func get(functionName: String, query: [URLQueryItem], timeout: TimeInterval) async throws -> Data
}

/// A transport-layer failure for the crash-alert Edge Functions. Carries the
/// HTTP `statusCode` (when the server replied) and the raw error-body bytes so
/// the notifier can decode the contract's `{ code, retryable }` shape without
/// importing the Supabase SDK. A `nil` `statusCode` is a transport/offline
/// error (retryable); `isTimeout` marks the unknown-outcome timeout case.
///
/// The body is the backend's structured error JSON only (§5.3/§13): it never
/// contains phone numbers, message bodies, or coordinates.
nonisolated struct CrashTransportError: Error, Sendable {
    let statusCode: Int?
    let body: Data?
    let isTimeout: Bool

    init(statusCode: Int?, body: Data? = nil, isTimeout: Bool = false) {
        self.statusCode = statusCode
        self.body = body
        self.isTimeout = isTimeout
    }
}
