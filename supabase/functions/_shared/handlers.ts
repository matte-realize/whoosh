/**
 * Crash-alert request handling (contract sections 5 to 8), independent of Supabase and Twilio.
 * The Edge Functions in ../<name>/index.ts wire these handlers to the database (service role) and
 * the provider. `handlers-check.ts` runs them against an in-memory store.
 */

import { render, segmentCount, type Kind } from "./template.ts";
import { SCHEMA_VERSION, MAX_BODY_BYTES, validateSendRequest, type SendRequest } from "./validate.ts";
import { lastTwo, mapProviderError, mapProviderStatus, recipientHash, verifyTwilioSignature, type DeliveryStatus, type SendResult } from "./provider.ts";

// ---------- Types shared with the store ----------

export interface Config {
  enabled: boolean;
  trialMode: boolean;
  minSchemaVersion: number;
  minConsentVersion: number;
  supportedTemplateVersions: number[];
  maxRecipientsPerRequest: number;
  realAlertsPerUser24h: number;
  testMessagesPerUser24h: number;
  testMessagesPerRecipient24h: number;
  newRecipientsPerUser24h: number;
  realPerRecipientAllUsers24h: number;
  testPerRecipientAllUsers24h: number;
  burstRequestsPerMinute: number;
  globalMessagesPerHour: number;
  maxSegments: number;
}

export interface EventRow {
  id: string;
  userId: string;
  crashEventId: string;
  kind: Kind;
  templateVersion: number;
  consentVersion: number;
  detectedAt: string;
  delayedSeconds: number;
  locationStatus: "current" | "last_known" | "unavailable" | "none";
  appVersion: string;
  createdAt: string;
  /** Not a column: the label is never stored. Compared through labelHash instead. */
}

export interface DeliveryRow {
  id: string;
  eventId: string;
  userId: string;
  recipientRef: string;
  recipientHash: string;
  recipientLast2: string;
  provider: string;
  providerMessageSid: string | null;
  status: DeliveryStatus;
  whooshErrorCode: string | null;
  providerErrorCode: number | null;
  segments: number;
  attemptCount: number;
  updatedAt: string;
}

export type Bucket = "real_alert" | "test_message" | "new_recipient" | "recipient_real" | "recipient_test" | "burst" | "global_message";

/** What the handlers need from the database. The Edge Functions implement it with the service role. */
export interface CrashStore {
  getConfig(): Promise<Config>;
  findEvent(userId: string, crashEventId: string, kind: Kind): Promise<EventRow | null>;
  /** Inserts under the unique (user, crash event, kind) key; returns the existing row if it lost a race. */
  insertEvent(row: Omit<EventRow, "id" | "createdAt">): Promise<{ row: EventRow; created: boolean }>;
  deleteEvent(id: string): Promise<void>;
  findDelivery(eventId: string, recipientHash: string): Promise<DeliveryRow | null>;
  /** Inserts under the unique (event, recipient hash) key; returns the existing row if it lost a race. */
  insertDelivery(row: Omit<DeliveryRow, "id" | "updatedAt">): Promise<{ row: DeliveryRow; created: boolean }>;
  updateDelivery(id: string, patch: Partial<DeliveryRow>): Promise<DeliveryRow>;
  listDeliveries(eventId: string): Promise<DeliveryRow[]>;
  /** public.crash_alert_take: true if a unit was taken. A null hash means "any recipient". */
  take(userId: string, bucket: Bucket, recipientHash: string | null, limit: number, windowSeconds: number, acrossUsers: boolean): Promise<boolean>;
  /** Counter rows for one user and bucket in the window (for the `limits` block of the response). */
  countUserBucket(userId: string, bucket: Bucket, windowSeconds: number): Promise<number>;
  /** True if this user already sent anything to this recipient in the window. */
  hasRecentRecipient(userId: string, recipientHash: string, windowSeconds: number): Promise<boolean>;
  /** public.crash_alert_apply_status. */
  applyStatus(sid: string, status: DeliveryStatus, providerErrorCode: number | null, whooshErrorCode: string | null): Promise<string>;
  /** Events of this user, optionally one crash event, with their creation times. */
  listUserEvents(userId: string, crashEventId: string | null): Promise<EventRow[]>;
  deleteEvents(ids: string[]): Promise<number>;
}

export interface Deps {
  store: CrashStore;
  /** Sends one text. Must not throw for provider errors (see provider.ts). */
  send: (to: string, body: string) => Promise<SendResult>;
  pepper: string;
  now: () => Date;
  requestId: () => string;
  provider: string;
  /** Logs PII-free fields only (contract section 12). */
  log: (event: string, fields: Record<string, string | number | boolean | null>) => void;
}

export interface Reply {
  status: number;
  body: Record<string, unknown>;
  headers?: Record<string, string>;
}

const DAY = 86_400;

function error(deps: Deps, status: number, code: string, retryable: boolean, extra: Record<string, unknown> = {}): Reply {
  return { status, body: { schemaVersion: SCHEMA_VERSION, requestId: deps.requestId(), code, retryable, ...extra } };
}

function locationStatus(request: SendRequest): EventRow["locationStatus"] {
  return request.location === undefined ? "none" : request.location.status;
}

function recipientResult(row: DeliveryRow) {
  return {
    recipientRef: row.recipientRef,
    status: row.status,
    errorCode: row.whooshErrorCode,
    providerErrorCode: row.providerErrorCode,
    segments: row.segments,
    updatedAt: row.updatedAt,
  };
}

async function limitsBlock(deps: Deps, userId: string, config: Config) {
  const [real, test] = await Promise.all([
    deps.store.countUserBucket(userId, "real_alert", DAY),
    deps.store.countUserBucket(userId, "test_message", DAY),
  ]);
  return {
    realAlertsRemaining24h: Math.max(0, config.realAlertsPerUser24h - real),
    testMessagesRemaining24h: Math.max(0, config.testMessagesPerUser24h - test),
  };
}

// ---------- send-crash-alert (contract 5) ----------

export async function handleSend(deps: Deps, userId: string, rawBody: string): Promise<Reply> {
  const { store } = deps;
  const config = await store.getConfig();

  // 2. Kill switch.
  if (!config.enabled) return error(deps, 503, "service_disabled", false);

  // 3. Validate.
  if (new TextEncoder().encode(rawBody).length > MAX_BODY_BYTES) return error(deps, 413, "payload_too_large", false);
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return error(deps, 400, "invalid_request", false);
  }
  const validation = validateSendRequest(
    parsed,
    {
      supportedTemplateVersions: config.supportedTemplateVersions,
      minConsentVersion: config.minConsentVersion,
      minSchemaVersion: config.minSchemaVersion,
      maxRecipients: config.maxRecipientsPerRequest,
    },
    deps.now(),
  );
  if (!validation.ok) return error(deps, validation.status, validation.code, false);
  const request = validation.request;
  const isReal = request.kind === "crash_alert";

  // Burst limit on this endpoint, before any other work.
  if (!(await store.take(userId, "burst", null, config.burstRequestsPerMinute, 60, false))) {
    return { ...error(deps, 429, "rate_limited", true, { scope: "burst", retryAfterSeconds: 60 }), headers: { "Retry-After": "60" } };
  }

  // 4. Keyed hashes.
  const hashes = await Promise.all(request.recipients.map((r) => recipientHash(deps.pepper, r.e164)));

  // 5. Idempotency. The real-alert cap applies only when the event is new, and is checked before
  // the event row exists, so a refused event can be retried later without bypassing the cap.
  let event = await store.findEvent(userId, request.crashEventId, request.kind);
  if (event === null) {
    if (isReal && !(await store.take(userId, "real_alert", null, config.realAlertsPerUser24h, DAY, false))) {
      return error(deps, 429, "rate_limited", false, { scope: "real_alert" });
    }
    const inserted = await store.insertEvent({
      userId,
      crashEventId: request.crashEventId,
      kind: request.kind,
      templateVersion: request.templateVersion,
      consentVersion: request.consent.version,
      detectedAt: new Date(request.detectedAt).toISOString(),
      delayedSeconds: request.delayedSeconds,
      locationStatus: locationStatus(request),
      appVersion: request.appVersion,
    });
    event = inserted.row;
  }
  // Immutable fields must match a stored event (the label is not stored, so it is not compared).
  if (
    event.templateVersion !== request.templateVersion ||
    Date.parse(event.detectedAt) !== Date.parse(request.detectedAt)
  ) {
    return error(deps, 409, "idempotency_conflict", false);
  }

  // 7. Per recipient.
  const results: DeliveryRow[] = [];
  let allDuplicates = true;
  for (let i = 0; i < request.recipients.length; i += 1) {
    const recipient = request.recipients[i];
    const hash = hashes[i];
    const existing = await store.findDelivery(event.id, hash);

    // Unknown-outcome policy (contract 13): a row with no sid may be re-attempted once.
    if (existing !== null) {
      const retryable = existing.providerMessageSid === null && existing.status === "queued" && existing.attemptCount < 2;
      if (!retryable) {
        results.push(existing);
        continue;
      }
      allDuplicates = false;
      results.push(await attemptSend(deps, config, request, recipient.e164, existing));
      continue;
    }
    allDuplicates = false;

    // 6. Caps for a new delivery (contract 10). Each unit taken stays taken (no refunds).
    const rejectReason = await checkRecipientCaps(deps, config, userId, hash, isReal);
    const created = await store.insertDelivery({
      eventId: event.id,
      userId,
      recipientRef: recipient.recipientRef,
      recipientHash: hash,
      recipientLast2: lastTwo(recipient.e164),
      provider: deps.provider,
      providerMessageSid: null,
      status: rejectReason ? "rejected" : "queued",
      whooshErrorCode: rejectReason,
      providerErrorCode: null,
      segments: 0,
      attemptCount: 0,
    });
    if (!created.created || rejectReason) {
      results.push(created.row);
      continue;
    }
    results.push(await attemptSend(deps, config, request, recipient.e164, created.row));
  }

  deps.log("send", {
    kind: request.kind,
    recipients: results.length,
    queued: results.filter((r) => r.status === "queued" || r.status === "sent").length,
    deduplicated: allDuplicates,
  });

  return {
    status: 200,
    body: {
      schemaVersion: SCHEMA_VERSION,
      requestId: deps.requestId(),
      crashEventId: request.crashEventId,
      kind: request.kind,
      deduplicated: allDuplicates,
      recipients: results.map(recipientResult),
      limits: await limitsBlock(deps, userId, config),
      serverTime: deps.now().toISOString(),
    },
  };
}

/** Returns a rejection code, or null when every cap allows this message. */
async function checkRecipientCaps(deps: Deps, config: Config, userId: string, hash: string, isReal: boolean): Promise<string | null> {
  const { store } = deps;
  if (!(await store.hasRecentRecipient(userId, hash, DAY))) {
    if (!(await store.take(userId, "new_recipient", null, config.newRecipientsPerUser24h, DAY, false))) {
      return "rate_limited_recipient";
    }
  }
  if (isReal) {
    if (!(await store.take(userId, "recipient_real", hash, config.realPerRecipientAllUsers24h, DAY, true))) {
      return "rate_limited_recipient";
    }
  } else {
    if (!(await store.take(userId, "test_message", null, config.testMessagesPerUser24h, DAY, false))) {
      return "rate_limited";
    }
    // The across-users cap is checked; the per-user one (same bucket) is implied while
    // testMessagesPerRecipient24h >= testPerRecipientAllUsers24h, which holds for the defaults.
    const perRecipient = Math.min(config.testMessagesPerRecipient24h, config.testPerRecipientAllUsers24h);
    if (!(await store.take(userId, "recipient_test", hash, perRecipient, DAY, true))) {
      return "rate_limited_recipient";
    }
  }
  if (!(await store.take(userId, "global_message", null, config.globalMessagesPerHour, 3600, true))) {
    return "rate_limited";
  }
  return null;
}

async function attemptSend(deps: Deps, config: Config, request: SendRequest, to: string, row: DeliveryRow): Promise<DeliveryRow> {
  let body: string;
  try {
    body = render(request);
  } catch {
    return deps.store.updateDelivery(row.id, { status: "rejected", whooshErrorCode: "message_too_long" });
  }
  const segments = segmentCount(body);
  if (segments > config.maxSegments) {
    return deps.store.updateDelivery(row.id, { status: "rejected", whooshErrorCode: "message_too_long", segments });
  }
  // Count the attempt before calling the provider, so a lost response can't cause unlimited retries.
  await deps.store.updateDelivery(row.id, { attemptCount: row.attemptCount + 1, segments });
  let result: SendResult;
  try {
    result = await deps.send(to, body);
  } catch {
    // Network failure or timeout: outcome unknown. Leave the row queued with no sid.
    return deps.store.updateDelivery(row.id, {});
  }
  if (result.ok) {
    return deps.store.updateDelivery(row.id, { providerMessageSid: result.sid, status: result.status });
  }
  if (result.providerErrorCode !== null) {
    return deps.store.updateDelivery(row.id, {
      status: "rejected",
      providerErrorCode: result.providerErrorCode,
      whooshErrorCode: mapProviderError(result.providerErrorCode),
    });
  }
  return deps.store.updateDelivery(row.id, {});
}

// ---------- crash-alert-status (contract 6) ----------

export async function handleStatus(deps: Deps, userId: string, crashEventId: string | null, kind: string | null): Promise<Reply> {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const k = (kind ?? "crash_alert") as Kind;
  if (crashEventId === null || !uuid.test(crashEventId) || !["crash_alert", "drill", "test", "intro", "all_clear"].includes(k)) {
    return error(deps, 400, "invalid_request", false);
  }
  const event = await deps.store.findEvent(userId, crashEventId, k);
  if (event === null) return error(deps, 404, "unknown_event", false);
  const config = await deps.store.getConfig();
  const deliveries = await deps.store.listDeliveries(event.id);
  return {
    status: 200,
    body: {
      schemaVersion: SCHEMA_VERSION,
      requestId: deps.requestId(),
      crashEventId,
      kind: k,
      recipients: deliveries.map(recipientResult),
      limits: await limitsBlock(deps, userId, config),
      serverTime: deps.now().toISOString(),
    },
  };
}

// ---------- sms-status-callback (contract 7) ----------

export async function handleCallback(
  deps: Deps,
  authToken: string,
  publicUrl: string,
  params: Record<string, string>,
  signature: string | null,
): Promise<Reply> {
  // Reject unsigned or invalid requests before touching the database.
  if (!(await verifyTwilioSignature(authToken, publicUrl, params, signature))) {
    return { status: 403, body: { code: "invalid_signature" } };
  }
  const sid = params.MessageSid;
  const status = mapProviderStatus(params.MessageStatus ?? "");
  if (!sid || status === null) {
    deps.log("callback_ignored", { reason: !sid ? "no_sid" : "unknown_status" });
    return { status: 200, body: {} };
  }
  const providerCode = params.ErrorCode ? Number(params.ErrorCode) : null;
  const outcome = await deps.store.applyStatus(
    sid,
    status,
    Number.isFinite(providerCode) ? providerCode : null,
    Number.isFinite(providerCode) ? mapProviderError(providerCode) : null,
  );
  deps.log("callback", { status, outcome });
  return { status: 200, body: {} };
}

// ---------- delete-crash-audit (contract 8) ----------

export async function handleDelete(deps: Deps, userId: string, rawBody: string): Promise<Reply> {
  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return error(deps, 400, "invalid_request", false);
  }
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const isAll = typeof body === "object" && body !== null && (body as Record<string, unknown>).all === true && Object.keys(body).length === 1;
  const id = typeof body === "object" && body !== null ? (body as Record<string, unknown>).crashEventId : undefined;
  const isOne = typeof id === "string" && uuid.test(id) && Object.keys(body as object).length === 1;
  if (!isAll && !isOne) return error(deps, 400, "invalid_request", false);

  const events = await deps.store.listUserEvents(userId, isOne ? (id as string) : null);
  const cutoff = deps.now().getTime() - 3600_000;
  // A mid-incident delete must not reset deduplication: refuse if any matching event is under 1 h old.
  if (events.some((e) => Date.parse(e.createdAt) > cutoff)) return error(deps, 409, "too_recent", false);
  const deleted = await deps.store.deleteEvents(events.map((e) => e.id));
  return { status: 200, body: { deleted } };
}
