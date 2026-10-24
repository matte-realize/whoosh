// send-crash-alert — validate, dedupe, rate-limit, render, and send crash-alert SMS.
// Contract: .kiro/team/crash-alert-contract.md §5, §10, §11, §12, Appendix A.
// Processing order follows §5.4 exactly.
//
// Logging rule (§12): logs may contain requestId, user_id, crash_event_id, kind, statuses,
// error codes, counts, timings — never phone numbers, labels, coordinates, or message bodies.

import {
  loadConfig,
  envKillSwitchOn,
  serviceClient,
  statusCallbackUrl,
  twilioCreds,
  userClient,
  validityPeriodSeconds,
} from "../_shared/env.ts";
import { errorResponse, jsonResponse, requestId, SCHEMA_VERSION, serverTime } from "../_shared/http.ts";
import { last2, recipientHash } from "../_shared/hash.ts";
import { renderMessage } from "../_shared/message.ts";
import type { Kind } from "../_shared/message.ts";
import { type SendRequest, validateRequest } from "../_shared/validation.ts";
import {
  checkRecipientLimits,
  checkUserLimits,
  isTestKind,
  recordBurst,
  recordSend,
} from "../_shared/limits.ts";
import { mapProviderErrorCode, sendSms } from "../_shared/twilio.ts";

interface RecipientResult {
  recipientRef: string;
  status: string;
  errorCode: string | null;
  providerErrorCode: number | null;
  segments: number;
  updatedAt: string;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const rid = requestId();
  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed");
  }

  // 1. Verify JWT: read user_id via the user-scoped client.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return errorResponse(401, "unauthenticated", { retryable: true });
  }
  let userId: string;
  try {
    const uc = userClient(authHeader);
    const { data, error } = await uc.auth.getUser();
    if (error || !data.user) {
      return errorResponse(401, "unauthenticated", { retryable: true });
    }
    userId = data.user.id;
  } catch {
    return errorResponse(401, "unauthenticated", { retryable: true });
  }

  const svc = serviceClient();

  // 2. Kill switch (env flag or config).
  let cfg;
  try {
    cfg = await loadConfig(svc);
  } catch {
    return errorResponse(500, "server_error", { retryable: true });
  }
  if (envKillSwitchOn() || !cfg.enabled) {
    return errorResponse(503, "service_disabled", { retryable: false });
  }

  // Body size <= 4 KB (§5.3).
  const raw = await req.text();
  if (raw.length > 4096) {
    return errorResponse(413, "payload_too_large");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return errorResponse(400, "invalid_request");
  }

  // 3. Validate (§5.3).
  const vErr = validateRequest(
    parsed,
    {
      minSchemaVersion: cfg.min_schema_version,
      supportedTemplateVersions: cfg.supported_template_versions,
      minConsentVersion: cfg.min_consent_version,
      recipientsPerRequest: cfg.recipients_per_request,
    },
    new Date(),
  );
  if (vErr) {
    return errorResponse(vErr.status, vErr.code);
  }
  const body = parsed as SendRequest;
  const kind = body.kind as Kind;

  // all_clear requires an existing crash_alert event for the same user (contract §5.1 / C11).
  if (kind === "all_clear") {
    const { count } = await svc
      .from("crash_alert_events")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("kind", "crash_alert");
    if (!count || count < 1) {
      return errorResponse(422, "no_prior_crash_alert");
    }
  }

  // 5. Idempotency: insert the event row under (user_id, crash_event_id, kind).
  const locStatus = body.location?.status ?? "none";
  let eventId: string;
  let dedupeMode = false;
  {
    const { data: inserted, error: insErr } = await svc
      .from("crash_alert_events")
      .insert({
        user_id: userId,
        crash_event_id: body.crashEventId,
        kind,
        template_version: body.templateVersion,
        consent_version: body.consent.version,
        detected_at: body.detectedAt,
        delayed_seconds: body.delayedSeconds,
        location_status: locStatus,
        app_version: body.appVersion ?? null,
      })
      .select("id")
      .single();

    if (insErr) {
      // Row exists: fetch it and compare immutable fields.
      const { data: existing } = await svc
        .from("crash_alert_events")
        .select("id, kind, detected_at, template_version")
        .eq("user_id", userId)
        .eq("crash_event_id", body.crashEventId)
        .eq("kind", kind)
        .single();
      if (!existing) {
        return errorResponse(500, "server_error", { retryable: true });
      }
      // riderLabel is not stored (no PII); compare the immutable fields we do store.
      const mismatch = existing.detected_at !== body.detectedAt ||
        existing.template_version !== body.templateVersion;
      if (mismatch) {
        return errorResponse(409, "idempotency_conflict");
      }
      eventId = existing.id;
      dedupeMode = true;
    } else {
      eventId = inserted.id;
    }
  }

  // 6. Per-user rate limits and caps. A per-user cap hit rejects the whole request (429).
  // Record a burst event first so repeated requests still count even if rejected.
  await recordBurst(svc, userId);
  const userLimit = await checkUserLimits(svc, userId, kind, cfg);
  if (userLimit.scope) {
    const retryable = userLimit.scope === "burst";
    return errorResponse(429, "rate_limited", {
      retryable,
      scope: userLimit.scope,
      retryAfterSeconds: userLimit.retryAfterSeconds,
    });
  }

  // Render once (identical body for every recipient of this event).
  const rendered = renderMessage({
    kind,
    riderLabel: body.riderLabel,
    detectedAt: body.detectedAt,
    utcOffsetMinutes: body.utcOffsetMinutes,
    delayedSeconds: body.delayedSeconds,
    location: body.location,
  });
  // Segments cap (§10): longer renders are rejected server-side.
  if (rendered.segments > cfg.max_segments) {
    return errorResponse(422, "message_too_long");
  }

  let creds;
  let callbackUrl;
  let validity;
  let pepper: string;
  try {
    creds = twilioCreds();
    callbackUrl = statusCallbackUrl();
    validity = validityPeriodSeconds();
    const p = Deno.env.get("RECIPIENT_HASH_PEPPER");
    if (!p) throw new Error("missing required secret: RECIPIENT_HASH_PEPPER");
    pepper = p;
  } catch {
    return errorResponse(500, "server_error", { retryable: true });
  }

  // 7. Per-recipient handling.
  const results: RecipientResult[] = [];
  let allDeduplicated = true;

  for (const r of body.recipients) {
    const now = serverTime();
    const hash = await recipientHash(r.e164, pepper);
    const l2 = last2(r.e164);

    // Insert the delivery row under (event_id, recipient_hash). If it exists, do not send.
    const { data: existingDel } = await svc
      .from("crash_alert_deliveries")
      .select("status, whoosh_error_code, provider_error_code, segments, updated_at")
      .eq("event_id", eventId)
      .eq("recipient_hash", hash)
      .maybeSingle();

    if (existingDel) {
      results.push({
        recipientRef: r.recipientRef,
        status: existingDel.status,
        errorCode: existingDel.whoosh_error_code,
        providerErrorCode: existingDel.provider_error_code,
        segments: existingDel.segments,
        updatedAt: existingDel.updated_at,
      });
      continue;
    }
    allDeduplicated = false;

    // Per-recipient caps (do not fail the whole request).
    const recLimit = await checkRecipientLimits(svc, userId, hash, kind, cfg);
    if (recLimit) {
      await svc.from("crash_alert_deliveries").insert({
        event_id: eventId,
        user_id: userId,
        recipient_ref: r.recipientRef,
        recipient_hash: hash,
        recipient_last2: l2,
        provider: "twilio",
        status: "rejected",
        whoosh_error_code: recLimit,
        segments: 0,
        attempt_count: 0,
        terminal_at: now,
      });
      results.push({
        recipientRef: r.recipientRef,
        status: "rejected",
        errorCode: recLimit,
        providerErrorCode: null,
        segments: 0,
        updatedAt: now,
      });
      continue;
    }

    // Insert the delivery row BEFORE the provider call (unknown-outcome policy, §13).
    const { data: delRow, error: delErr } = await svc
      .from("crash_alert_deliveries")
      .insert({
        event_id: eventId,
        user_id: userId,
        recipient_ref: r.recipientRef,
        recipient_hash: hash,
        recipient_last2: l2,
        provider: "twilio",
        status: "queued",
        segments: rendered.segments,
        attempt_count: 0,
      })
      .select("id")
      .single();

    if (delErr || !delRow) {
      // Lost a race: another request inserted the same row. Treat as deduplicated.
      const { data: raced } = await svc
        .from("crash_alert_deliveries")
        .select("status, whoosh_error_code, provider_error_code, segments, updated_at")
        .eq("event_id", eventId)
        .eq("recipient_hash", hash)
        .maybeSingle();
      results.push({
        recipientRef: r.recipientRef,
        status: raced?.status ?? "queued",
        errorCode: raced?.whoosh_error_code ?? null,
        providerErrorCode: raced?.provider_error_code ?? null,
        segments: raced?.segments ?? rendered.segments,
        updatedAt: raced?.updated_at ?? now,
      });
      continue;
    }

    // Call the provider exactly once.
    const send = await sendSms(creds, r.e164, rendered.body, callbackUrl, validity);
    if (send.ok) {
      await svc
        .from("crash_alert_deliveries")
        .update({
          provider_message_sid: send.sid,
          status: "queued",
          attempt_count: 1,
          updated_at: now,
        })
        .eq("id", delRow.id);
      await recordSend(svc, userId, hash, kind);
      results.push({
        recipientRef: r.recipientRef,
        status: "queued",
        errorCode: null,
        providerErrorCode: null,
        segments: rendered.segments,
        updatedAt: now,
      });
    } else {
      const mapped = mapProviderErrorCode(send.providerErrorCode);
      await svc
        .from("crash_alert_deliveries")
        .update({
          status: "rejected",
          whoosh_error_code: mapped,
          provider_error_code: send.providerErrorCode ?? null,
          attempt_count: 1,
          segments: 0,
          updated_at: now,
          terminal_at: now,
        })
        .eq("id", delRow.id);
      results.push({
        recipientRef: r.recipientRef,
        status: "rejected",
        errorCode: mapped,
        providerErrorCode: send.providerErrorCode ?? null,
        segments: 0,
        updatedAt: now,
      });
    }
  }

  // PII-free log line.
  console.log(JSON.stringify({
    requestId: rid,
    userId,
    crashEventId: body.crashEventId,
    kind,
    dedupeMode,
    recipients: results.map((r) => ({ status: r.status, errorCode: r.errorCode })),
  }));

  return jsonResponse(200, {
    schemaVersion: SCHEMA_VERSION,
    requestId: rid,
    crashEventId: body.crashEventId,
    kind,
    deduplicated: dedupeMode && allDeduplicated,
    recipients: results,
    serverTime: serverTime(),
  });
});
