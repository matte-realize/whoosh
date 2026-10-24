// crash-alert-status — per-user delivery status read (contract §6).
//
// GET /functions/v1/crash-alert-status?crashEventId=<uuid>&kind=crash_alert
// Auth: Supabase JWT. Reads only the caller's own rows (enforced by RLS via the user client).
// kind defaults to crash_alert. 404 unknown_event when no such event exists for the caller.

import { userClient } from "../_shared/env.ts";
import { errorResponse, jsonResponse, requestId, SCHEMA_VERSION, serverTime } from "../_shared/http.ts";

const KINDS = new Set(["crash_alert", "drill", "test", "intro", "all_clear"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve(async (req: Request): Promise<Response> => {
  const rid = requestId();
  if (req.method !== "GET") {
    return errorResponse(405, "method_not_allowed");
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return errorResponse(401, "unauthenticated", { retryable: true });
  }

  const url = new URL(req.url);
  const crashEventId = url.searchParams.get("crashEventId") ?? "";
  const kind = url.searchParams.get("kind") ?? "crash_alert";
  if (!UUID_RE.test(crashEventId)) {
    return errorResponse(400, "invalid_request");
  }
  if (!KINDS.has(kind)) {
    return errorResponse(400, "invalid_request");
  }

  let uc;
  let userId: string;
  try {
    uc = userClient(authHeader);
    const { data, error } = await uc.auth.getUser();
    if (error || !data.user) {
      return errorResponse(401, "unauthenticated", { retryable: true });
    }
    userId = data.user.id;
  } catch {
    return errorResponse(401, "unauthenticated", { retryable: true });
  }

  // The event row (RLS limits this to the caller's own rows). user_id filter is belt-and-braces.
  const { data: event, error: evErr } = await uc
    .from("crash_alert_events")
    .select("id")
    .eq("user_id", userId)
    .eq("crash_event_id", crashEventId)
    .eq("kind", kind)
    .maybeSingle();
  if (evErr) {
    return errorResponse(500, "server_error", { retryable: true });
  }
  if (!event) {
    return errorResponse(404, "unknown_event");
  }

  const { data: deliveries, error: delErr } = await uc
    .from("crash_alert_deliveries")
    .select("recipient_ref, status, whoosh_error_code, provider_error_code, segments, updated_at")
    .eq("event_id", event.id);
  if (delErr) {
    return errorResponse(500, "server_error", { retryable: true });
  }

  const recipients = (deliveries ?? []).map((d) => ({
    recipientRef: d.recipient_ref,
    status: d.status,
    errorCode: d.whoosh_error_code,
    providerErrorCode: d.provider_error_code,
    segments: d.segments,
    updatedAt: d.updated_at,
  }));

  return jsonResponse(200, {
    schemaVersion: SCHEMA_VERSION,
    requestId: rid,
    crashEventId,
    kind,
    recipients,
    serverTime: serverTime(),
  });
});
