// sms-status-callback — provider -> backend delivery status callback (contract §7).
//
// Auth: NO Supabase JWT. The provider's request signature is validated instead. Deploy with
// `--no-verify-jwt` (see README) so Supabase does not require an Authorization header.
//
// Rules: validate the X-Twilio-Signature before touching the DB; apply monotonic/sticky status
// updates; idempotent for duplicate and out-of-order callbacks; always respond 200 quickly after
// a valid signature so the provider does not retry-storm. Unknown sid => 200 (ack, ignore).

import { getEnv, serviceClient } from "../_shared/env.ts";
import {
  canApplyStatus,
  isValidTwilioSignature,
  mapProviderErrorCode,
  mapProviderStatus,
  type WhooshStatus,
} from "../_shared/twilio.ts";

const TERMINAL = new Set<WhooshStatus>(["delivered", "undelivered", "failed", "rejected"]);

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Parse the form-encoded body into a plain map for signature validation.
  const rawBody = await req.text();
  const form = new URLSearchParams(rawBody);
  const params: Record<string, string> = {};
  for (const [k, v] of form.entries()) params[k] = v;

  // Validate the signature over the full request URL + sorted POST params.
  const signature = req.headers.get("X-Twilio-Signature") ?? "";
  let authToken: string;
  try {
    authToken = getEnv("TWILIO_AUTH_TOKEN");
  } catch {
    return new Response("server error", { status: 500 });
  }

  // The signed URL must match what Twilio used. CALLBACK_BASE_URL + path is the source of truth;
  // fall back to the request URL if not set.
  const signedUrl = callbackUrlFor(req);
  const valid = await isValidTwilioSignature(authToken, signedUrl, params, signature);
  if (!valid) {
    // Reject before any DB access (contract §7, §12).
    return new Response("invalid signature", { status: 403 });
  }

  const sid = params["MessageSid"];
  const messageStatus = params["MessageStatus"];
  const errorCodeRaw = params["ErrorCode"];
  if (!sid || !messageStatus) {
    // Valid signature but nothing actionable: acknowledge.
    return new Response("ok", { status: 200 });
  }

  const svc = serviceClient();

  // Lookup by provider_message_sid. Unknown sid => 200 (ack, ignore, count).
  const { data: row } = await svc
    .from("crash_alert_deliveries")
    .select("id, status")
    .eq("provider_message_sid", sid)
    .maybeSingle();

  if (!row) {
    console.log(JSON.stringify({ callback: "unknown_sid", messageStatus }));
    return new Response("ok", { status: 200 });
  }

  const next = mapProviderStatus(messageStatus);
  if (next === null) {
    // Ignored status (logged only).
    console.log(JSON.stringify({ callback: "ignored_status", messageStatus }));
    return new Response("ok", { status: 200 });
  }

  const current = row.status as WhooshStatus;
  if (!canApplyStatus(current, next)) {
    // Monotonic/sticky: out-of-order or conflicting terminal status — count, do not apply.
    console.log(JSON.stringify({ callback: "not_applied", from: current, to: next }));
    return new Response("ok", { status: 200 });
  }

  const nowIso = new Date().toISOString();
  const providerErrorCode = errorCodeRaw ? Number(errorCodeRaw) : undefined;
  const update: Record<string, unknown> = {
    status: next,
    updated_at: nowIso,
  };
  if (providerErrorCode !== undefined && Number.isFinite(providerErrorCode)) {
    update.provider_error_code = providerErrorCode;
    const mapped = mapProviderErrorCode(providerErrorCode);
    if (mapped) update.whoosh_error_code = mapped;
  }
  if (TERMINAL.has(next)) update.terminal_at = nowIso;

  await svc.from("crash_alert_deliveries").update(update).eq("id", row.id);

  console.log(JSON.stringify({ callback: "applied", from: current, to: next }));
  return new Response("ok", { status: 200 });
});

function callbackUrlFor(req: Request): string {
  const base = Deno.env.get("CALLBACK_BASE_URL");
  if (base) return `${base.replace(/\/$/, "")}/sms-status-callback`;
  return req.url;
}
