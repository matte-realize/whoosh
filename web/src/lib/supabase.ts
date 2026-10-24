import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | null = null;

/**
 * Returns a lazily created browser client, or null when the public env vars are missing
 * or still hold the placeholders from .env.example.
 *
 * Uses only the NEXT_PUBLIC_ URL and publishable key. The site never signs in: the requests
 * run as role `anon`, which can read the `public_rides` view. Signing in (even anonymously)
 * would switch the role to `authenticated`, which has no access to the view.
 */
export function getSupabaseClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !key) return null;
  if (url.includes("YOUR-PROJECT-REF") || key.includes("REPLACE_ME")) return null;

  client ??= createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  return client;
}
