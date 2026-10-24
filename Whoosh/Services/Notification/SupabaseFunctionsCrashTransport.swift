import Foundation
import Supabase

/// The one crash-alert type that talks to the Supabase SDK (crash-response
/// task 25), mirroring `SupabaseRideSyncTransport`.
///
/// Implements `CrashNotifierTransport` by driving the shared `SupabaseClient`:
/// an anonymous sign-in for the session (the SDK then attaches the
/// `Authorization: Bearer <jwt>` and `apikey` headers to every Edge Function
/// call automatically, contract §3), and `functions.invoke` for
/// `send-crash-alert` (POST) and `crash-alert-status` (GET). The raw response
/// bytes are handed back to `SupabaseCrashNotifier` for decoding; a non-2xx
/// `FunctionsError.httpError` becomes a `CrashTransportError` carrying the
/// status and the (PII-free) error body, a `URLError.timedOut` becomes a
/// timeout, and any other transport error becomes an offline
/// (`statusCode == nil`) error.
///
/// An `actor` so all network work stays off the main actor. Lives in
/// `Services/Notification`, the only crash folder allowed to import `Supabase` /
/// touch the network (privacy steering).
actor SupabaseFunctionsCrashTransport: CrashNotifierTransport {
    private let client: SupabaseClient
    private var hasSession = false

    init(client: SupabaseClient) {
        self.client = client
    }

    func ensureSession() async throws {
        do {
            _ = try await client.auth.session
            hasSession = true
        } catch {
            do {
                _ = try await client.auth.signInAnonymously()
                hasSession = true
            } catch {
                // No session and sign-in failed ⇒ treat as offline/retryable.
                throw Self.map(error)
            }
        }
    }

    func post(functionName: String, body: Data, timeout: TimeInterval) async throws -> Data {
        try await invokeRaw(
            functionName,
            options: FunctionInvokeOptions(
                method: .post,
                body: body,
                timeoutInterval: timeout
            )
        )
    }

    func get(functionName: String, query: [URLQueryItem], timeout: TimeInterval) async throws -> Data {
        try await invokeRaw(
            functionName,
            options: FunctionInvokeOptions(
                method: .get,
                query: query,
                timeoutInterval: timeout
            )
        )
    }

    // MARK: - Invoke + error mapping

    private func invokeRaw(_ functionName: String, options: FunctionInvokeOptions) async throws -> Data {
        do {
            return try await client.functions.invoke(functionName, options: options) { data, _ in data }
        } catch {
            throw Self.map(error)
        }
    }

    /// Convert an SDK/URL error into a `CrashTransportError`. An
    /// `httpError(code:data:)` keeps the status and body so the notifier can
    /// decode the contract's structured error; a timeout is flagged; everything
    /// else is an offline (`statusCode == nil`) error.
    private nonisolated static func map(_ error: Error) -> CrashTransportError {
        if let transport = error as? CrashTransportError {
            return transport
        }
        if let functions = error as? FunctionsError {
            switch functions {
            case let .httpError(code, data):
                return CrashTransportError(statusCode: code, body: data)
            case .relayError:
                return CrashTransportError(statusCode: nil)
            }
        }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return CrashTransportError(statusCode: nil, isTimeout: true)
            }
            return CrashTransportError(statusCode: nil)
        }
        return CrashTransportError(statusCode: nil)
    }
}
