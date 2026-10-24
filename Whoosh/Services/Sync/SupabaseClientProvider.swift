import Foundation
import Supabase

/// Builds and owns the single `SupabaseClient` for opt-in sync (task 28e).
///
/// Reads the Supabase URL and publishable key from the app's Info.plist (set
/// from the gitignored `Secrets.xcconfig` via the `INFOPLIST_KEY_SUPABASE_*`
/// build settings — never hard-coded in Swift). If either value is missing or
/// still the placeholder, `isConfigured` is `false` and no client is built, so
/// sync is simply unavailable rather than crashing.
///
/// The SDK persists the anonymous session in the Keychain via its default
/// storage, so a returning user keeps the same anonymous `auth.uid()`. The only
/// place in the app that imports `Supabase`; lives in `Services/Sync` per the
/// privacy steering.
final class SupabaseClientProvider: Sendable {
    let client: SupabaseClient?

    /// Whether a usable URL + publishable key were found. When `false` the app
    /// still runs; sync just can't sign in.
    var isConfigured: Bool { client != nil }

    init(bundle: Bundle = .main) {
        self.client = Self.makeClient(bundle: bundle)
    }

    private static func makeClient(bundle: Bundle) -> SupabaseClient? {
        guard
            let urlString = infoValue(bundle, "SUPABASE_URL"),
            let key = infoValue(bundle, "SUPABASE_PUBLISHABLE_KEY"),
            let url = URL(string: urlString),
            url.scheme?.hasPrefix("http") == true
        else {
            return nil
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    /// Reads an Info.plist string, rejecting empty or placeholder values so a
    /// repo with only `Secrets.example.xcconfig` leaves sync unavailable.
    private static func infoValue(_ bundle: Bundle, _ key: String) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // Reject the committed example placeholders.
        if value.contains("example.supabase.co") { return nil }
        if value.hasPrefix("sb_publishable_your-") { return nil }
        if value == "your-anon-key-here" { return nil }
        return value
    }
}
