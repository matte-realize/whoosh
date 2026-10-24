// POST /functions/v1/sms-status-callback — contract section 7. Called by the provider, not the app.
// JWT verification is off for this function (supabase/config.toml); the provider signature is the
// only authentication, and it is checked before any database access.
import { handleCallback } from "../_shared/handlers.ts";
import { guarded, json, makeDeps, methodNotAllowed } from "../_shared/runtime.ts";

Deno.serve((req) =>
  guarded(async () => {
    if (req.method !== "POST") return methodNotAllowed();
    const form = new URLSearchParams(await req.text());
    const params: Record<string, string> = {};
    for (const [key, value] of form) params[key] = value;
    // Sign against the public URL the provider was given, not the internal request URL.
    const publicUrl = Deno.env.get("SMS_STATUS_CALLBACK_URL") ?? "";
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN") ?? "";
    if (!publicUrl || !authToken) return json({ status: 403, body: { code: "invalid_signature" } });
    return json(await handleCallback(makeDeps(), authToken, publicUrl, params, req.headers.get("X-Twilio-Signature")));
  }),
);

