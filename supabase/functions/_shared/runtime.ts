/**
 * Shared Edge Function plumbing (Deno): secrets, the service-role store, caller authentication,
 * JSON replies, and PII-free logging (contract section 12).
 *
 * Secrets (set with `supabase secrets set`, never committed):
 *   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM (MG... messaging service or +1 number),
 *   SMS_STATUS_CALLBACK_URL (public URL of sms-status-callback), CRASH_ALERT_PEPPER (32+ chars).
 * Supabase provides SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to Edge Functions automatically.
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import type { Deps, Reply } from "./handlers.ts";
import { sendTwilioMessage } from "./provider.ts";
import { SupabaseCrashStore } from "./supabase-store.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
}

export function makeDeps(): Deps {
  const store = new SupabaseCrashStore(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
  return {
    store,
    send: (to, body) =>
      sendTwilioMessage(
        {
          accountSid: env("TWILIO_ACCOUNT_SID"),
          authToken: env("TWILIO_AUTH_TOKEN"),
          from: env("TWILIO_FROM"),
          statusCallbackUrl: env("SMS_STATUS_CALLBACK_URL"),
          // Give up after 15 minutes rather than deliver an alert hours late (contract 10).
          validityPeriodSeconds: 900,
        },
        to,
        body,
      ),
    pepper: env("CRASH_ALERT_PEPPER"),
    now: () => new Date(),
    requestId: () => `req_${crypto.randomUUID().replaceAll("-", "")}`,
    provider: "twilio",
    log: (event, fields) => console.log(JSON.stringify({ event, ...fields })),
  };
}

/** Returns the caller's user id from their Supabase access token, or null. */
export async function callerId(req: Request): Promise<string | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return null;
  const client = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}

export function json(reply: Reply): Response {
  return new Response(JSON.stringify(reply.body), {
    status: reply.status,
    headers: { "Content-Type": "application/json", ...(reply.headers ?? {}) },
  });
}

export function unauthenticated(): Response {
  return json({ status: 401, body: { code: "unauthenticated", retryable: true } });
}

export function methodNotAllowed(): Response {
  return json({ status: 405, body: { code: "method_not_allowed", retryable: false } });
}

/** Never leak internals: any unexpected error becomes a retryable 500 with no detail. */
export async function guarded(handler: () => Promise<Response>): Promise<Response> {
  try {
    return await handler();
  } catch (err) {
    console.log(JSON.stringify({ event: "error", message: err instanceof Error ? err.message : "unknown" }));
    return json({ status: 500, body: { code: "internal_error", retryable: true } });
  }
}
