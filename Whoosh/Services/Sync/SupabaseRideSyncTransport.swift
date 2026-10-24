import Foundation
import Supabase

/// The one type that talks to the Supabase SDK (task 28e).
///
/// Implements `RideSyncTransport` by driving the shared `SupabaseClient`: an
/// anonymous sign-in for the session, a full-column upsert on `id` into `rides`,
/// a delete by `id`, and a `share_publicly`-only partial update. Any
/// `PostgrestError` is converted to a `SyncTransportError` carrying its `code`
/// so the service can classify it (`23514` permanent, `42501` auth-retry,
/// everything else retryable) without importing the SDK.
///
/// An `actor` so all network work stays off the main actor. Lives in
/// `Services/Sync`, the only folder allowed to import `Supabase` / touch the
/// network (privacy steering).
actor SupabaseRideSyncTransport: RideSyncTransport {
    private let client: SupabaseClient
    private let table = "rides"
    private var hasSession = false

    init(client: SupabaseClient) {
        self.client = client
    }

    func ensureSession() async throws {
        do {
            // Already signed in? `session` returns the current session or throws.
            _ = try await client.auth.session
            hasSession = true
        } catch {
            // No session yet (or it expired): anonymous sign-in. The SDK
            // persists it in the Keychain via its default storage.
            do {
                _ = try await client.auth.signInAnonymously()
                hasSession = true
            } catch {
                throw Self.map(error)
            }
        }
    }

    func upsert(_ row: RideUploadRow) async throws {
        do {
            try await client
                .from(table)
                .upsert(row, onConflict: "id", returning: .minimal)
                .execute()
        } catch {
            throw Self.map(error)
        }
    }

    func delete(id: UUID) async throws {
        do {
            try await client
                .from(table)
                .delete(returning: .minimal)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw Self.map(error)
        }
    }

    func updateSharing(id: UUID, shared: Bool) async throws {
        do {
            try await client
                .from(table)
                .update(["share_publicly": shared], returning: .minimal)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Error mapping

    /// Convert any SDK error into a `SyncTransportError` carrying the PostgREST
    /// `code` when present (so the service can classify it); otherwise a
    /// code-less (retryable) transport error.
    private nonisolated static func map(_ error: Error) -> SyncTransportError {
        if let error = error as? SyncTransportError {
            return error
        }
        if let postgrest = error as? PostgrestError {
            return SyncTransportError(code: postgrest.code, message: postgrest.message)
        }
        return SyncTransportError(code: nil, message: String(describing: error))
    }
}
