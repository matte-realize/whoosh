// Checks for handlers.ts against an in-memory store that mimics the SQL functions' rules.
// Run from the repo root:  node supabase/functions/_shared/handlers-check.ts   (Node 23.6+)
import {
  handleCallback,
  handleDelete,
  handleSend,
  handleStatus,
  type Bucket,
  type Config,
  type CrashStore,
  type DeliveryRow,
  type Deps,
  type EventRow,
} from "./handlers.ts";
import { twilioSignature, type DeliveryStatus, type SendResult } from "./provider.ts";
import type { Kind } from "./template.ts";

let failures = 0;
function check(ok: boolean, name: string, detail = ""): void {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok || !detail ? "" : `\n      ${detail}`}`);
  if (!ok) failures += 1;
}

const DEFAULT_CONFIG: Config = {
  enabled: true,
  trialMode: true,
  minSchemaVersion: 1,
  minConsentVersion: 1,
  supportedTemplateVersions: [1],
  maxRecipientsPerRequest: 3,
  realAlertsPerUser24h: 5,
  testMessagesPerUser24h: 10,
  testMessagesPerRecipient24h: 3,
  newRecipientsPerUser24h: 5,
  realPerRecipientAllUsers24h: 5,
  testPerRecipientAllUsers24h: 3,
  burstRequestsPerMinute: 10,
  globalMessagesPerHour: 200,
  maxSegments: 4,
};

const RANK: Record<DeliveryStatus, number> = { queued: 1, sent: 2, delivered: 3, undelivered: 3, failed: 3, rejected: 3 };

class MemoryStore implements CrashStore {
  config: Config = { ...DEFAULT_CONFIG };
  events: EventRow[] = [];
  deliveries: (DeliveryRow & { createdAt: string })[] = [];
  counters: { userId: string; bucket: Bucket; hash: string | null; at: number }[] = [];
  ids = 0;
  clock: () => Date;
  constructor(clock: () => Date) {
    this.clock = clock;
  }
  id() {
    this.ids += 1;
    return `00000000-0000-4000-8000-${String(this.ids).padStart(12, "0")}`;
  }
  async getConfig() {
    return this.config;
  }
  async findEvent(userId: string, crashEventId: string, kind: Kind) {
    return this.events.find((e) => e.userId === userId && e.crashEventId === crashEventId && e.kind === kind) ?? null;
  }
  async insertEvent(row: Omit<EventRow, "id" | "createdAt">) {
    const existing = await this.findEvent(row.userId, row.crashEventId, row.kind);
    if (existing) return { row: existing, created: false };
    const created = { ...row, id: this.id(), createdAt: this.clock().toISOString() };
    this.events.push(created);
    return { row: created, created: true };
  }
  async deleteEvent(id: string) {
    this.events = this.events.filter((e) => e.id !== id);
  }
  async findDelivery(eventId: string, hash: string) {
    return this.deliveries.find((d) => d.eventId === eventId && d.recipientHash === hash) ?? null;
  }
  async insertDelivery(row: Omit<DeliveryRow, "id" | "updatedAt">) {
    const existing = await this.findDelivery(row.eventId, row.recipientHash);
    if (existing) return { row: existing, created: false };
    const now = this.clock().toISOString();
    const created = { ...row, id: this.id(), updatedAt: now, createdAt: now };
    this.deliveries.push(created);
    return { row: created, created: true };
  }
  async updateDelivery(id: string, patch: Partial<DeliveryRow>) {
    const row = this.deliveries.find((d) => d.id === id);
    if (!row) throw new Error("no row");
    Object.assign(row, patch, { updatedAt: this.clock().toISOString() });
    return row;
  }
  async listDeliveries(eventId: string) {
    return this.deliveries.filter((d) => d.eventId === eventId);
  }
  async take(userId: string, bucket: Bucket, hash: string | null, limit: number, windowSeconds: number, across: boolean) {
    if (limit <= 0) return false;
    const since = this.clock().getTime() - windowSeconds * 1000;
    const n = this.counters.filter(
      (c) => c.bucket === bucket && c.at > since && (hash === null || c.hash === hash) && (across || c.userId === userId),
    ).length;
    if (n >= limit) return false;
    this.counters.push({ userId, bucket, hash, at: this.clock().getTime() });
    return true;
  }
  async countUserBucket(userId: string, bucket: Bucket, windowSeconds: number) {
    const since = this.clock().getTime() - windowSeconds * 1000;
    return this.counters.filter((c) => c.userId === userId && c.bucket === bucket && c.at > since).length;
  }
  async hasRecentRecipient(userId: string, hash: string, windowSeconds: number) {
    const since = this.clock().getTime() - windowSeconds * 1000;
    return this.deliveries.some((d) => d.userId === userId && d.recipientHash === hash && Date.parse(d.createdAt) > since);
  }
  async applyStatus(sid: string, status: DeliveryStatus, providerCode: number | null, whooshCode: string | null) {
    const row = this.deliveries.find((d) => d.providerMessageSid === sid);
    if (!row) return "unknown_sid";
    if (RANK[row.status] === 3 || RANK[status] <= RANK[row.status]) return "ignored";
    row.status = status;
    row.providerErrorCode = providerCode ?? row.providerErrorCode;
    row.whooshErrorCode = whooshCode ?? row.whooshErrorCode;
    return "applied";
  }
  async listUserEvents(userId: string, crashEventId: string | null) {
    return this.events.filter((e) => e.userId === userId && (crashEventId === null || e.crashEventId === crashEventId));
  }
  async deleteEvents(ids: string[]) {
    const before = this.events.length;
    this.events = this.events.filter((e) => !ids.includes(e.id));
    this.deliveries = this.deliveries.filter((d) => !ids.includes(d.eventId));
    return before - this.events.length;
  }
}

let nowMs = Date.parse("2026-10-24T17:45:00Z");
const clock = () => new Date(nowMs);
const advance = (seconds: number) => {
  nowMs += seconds * 1000;
};

function setup(sendImpl?: (to: string, body: string) => Promise<SendResult>) {
  const store = new MemoryStore(clock);
  const sent: { to: string; body: string }[] = [];
  let sid = 0;
  const logs: Record<string, unknown>[] = [];
  const deps: Deps = {
    store,
    send:
      sendImpl ??
      (async (to, body) => {
        sent.push({ to, body });
        sid += 1;
        return { ok: true, sid: `SM${sid}`, status: "queued", providerErrorCode: null };
      }),
    pepper: "p".repeat(32),
    now: clock,
    requestId: () => "req_test",
    provider: "twilio",
    log: (event, fields) => logs.push({ event, ...fields }),
  };
  return { store, deps, sent, logs };
}

const USER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
let eventSeq = 0;
function request(patch: Record<string, unknown> = {}) {
  eventSeq += 1;
  return {
    schemaVersion: 1,
    templateVersion: 1,
    crashEventId: `5b0b6f0e-2c0a-4a35-9a54-${String(eventSeq).padStart(12, "0")}`,
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: new Date(nowMs - 60_000).toISOString().replace(/\.\d{3}Z$/, "Z"),
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: { status: "current", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 12, ageSeconds: 0 },
    recipients: [
      { recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" },
      { recipientRef: "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f", e164: "+16175550124" },
    ],
    consent: { version: 1, acceptedAt: "2026-10-20T14:02:11Z" },
    appVersion: "1.0 (42)",
    ...patch,
  };
}
const body = (r: unknown) => JSON.stringify(r);
const statuses = (reply: { body: Record<string, unknown> }) =>
  ((reply.body.recipients as { status: string }[]) ?? []).map((r) => r.status).join(",");

// 1. Happy path: two messages, contract text, no PII in logs.
{
  const { deps, sent, logs } = setup();
  const reply = await handleSend(deps, USER, body(request()));
  check(reply.status === 200 && statuses(reply) === "queued,queued", `send: 200 with two queued recipients (${reply.status} ${statuses(reply)})`);
  check(sent.length === 2 && sent[0].body.startsWith("WHOOSH ALERT: Alex may have crashed"), "send: two texts with the alert template");
  check(reply.body.deduplicated === false, "send: deduplicated is false the first time");
  const logged = JSON.stringify(logs);
  check(!logged.includes("617555") && !logged.includes("Alex") && !logged.includes("42.36"), "send: logs contain no numbers, label, or coordinates");
}

// 2. Idempotency: the same request again sends nothing and reports deduplicated.
{
  const { deps, sent } = setup();
  const r = request();
  await handleSend(deps, USER, body(r));
  const again = await handleSend(deps, USER, body({ ...r, delayedSeconds: 120 }));
  check(sent.length === 2 && again.body.deduplicated === true, "idempotency: a retry sends nothing new and is deduplicated");
  const conflict = await handleSend(deps, USER, body({ ...r, detectedAt: new Date(nowMs - 120_000).toISOString().replace(/\.\d{3}Z$/, "Z") }));
  check(conflict.status === 409 && conflict.body.code === "idempotency_conflict", "idempotency: a changed detectedAt is a 409 conflict");
  const otherKind = await handleSend(deps, USER, body({ ...r, kind: "drill" }));
  check(otherKind.status === 200 && sent.length === 4, "idempotency: the same id with another kind is a separate event");
}

// 3. Retry with one recipient added: only the new one is sent.
{
  const { deps, sent } = setup();
  const r = request();
  await handleSend(deps, USER, body({ ...r, recipients: [r.recipients[0]] }));
  const reply = await handleSend(deps, USER, body(r));
  check(sent.length === 2 && sent[1].to === "+16175550124" && reply.body.deduplicated === false, "retry adds only the new recipient");
}

// 4. Kill switch, version gates, validation errors are non-retryable.
{
  const { deps, store, sent } = setup();
  store.config.enabled = false;
  const off = await handleSend(deps, USER, body(request()));
  check(off.status === 503 && off.body.code === "service_disabled" && off.body.retryable === false && sent.length === 0, "kill switch: 503 service_disabled, nothing sent");
  store.config.enabled = true;
  store.config.minConsentVersion = 2;
  const old = await handleSend(deps, USER, body(request()));
  check(old.status === 403 && old.body.code === "client_upgrade_required", "old consent version: 403 client_upgrade_required");
  store.config.minConsentVersion = 1;
  const bad = await handleSend(deps, USER, body(request({ riderLabel: "<script>" })));
  check(bad.status === 400 && bad.body.code === "invalid_label" && !JSON.stringify(bad.body).includes("script"), "bad label: 400 and the input is not echoed back");
  const big = await handleSend(deps, USER, "x".repeat(5000));
  check(big.status === 413 && big.body.code === "payload_too_large", "body over 4 KB: 413");
  const junk = await handleSend(deps, USER, "{not json");
  check(junk.status === 400 && junk.body.code === "invalid_request", "invalid JSON: 400");
}

// 5. Real-alert cap: 5 per user per day, then 429; the refused event can't be smuggled in later.
{
  const { deps, sent } = setup();
  for (let i = 0; i < 5; i += 1) await handleSend(deps, USER, body(request({ recipients: [{ recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: `+1617555013${i}` }] })));
  const sixth = await handleSend(deps, USER, body(request({ recipients: [{ recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550199" }] })));
  check(sixth.status === 429 && sixth.body.scope === "real_alert" && sixth.body.retryable === false, "real alerts: the 6th in a day is 429 real_alert");
  check(sent.length === 5, "real alerts: only 5 texts were sent");
}

// 6. Per-recipient cap across all users: one number gets at most 5 real alerts a day.
{
  const { deps, sent } = setup();
  const one = [{ recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" }];
  for (let i = 0; i < 3; i += 1) await handleSend(deps, USER, body(request({ recipients: one })));
  for (let i = 0; i < 2; i += 1) await handleSend(deps, OTHER, body(request({ recipients: one })));
  const extra = await handleSend(deps, OTHER, body(request({ recipients: one })));
  check(statuses(extra) === "rejected" && sent.length === 5, `recipient cap: the 6th real alert to one number is rejected (${statuses(extra)})`);
  const code = (extra.body.recipients as { errorCode: string }[])[0].errorCode;
  check(code === "rate_limited_recipient", "recipient cap: errorCode rate_limited_recipient");
}

// 7. Test-type messages: 3 per recipient, then rejected.
{
  const { deps, sent } = setup();
  const one = [{ recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" }];
  for (let i = 0; i < 3; i += 1) await handleSend(deps, USER, body(request({ kind: "test", location: undefined, recipients: one })));
  const fourth = await handleSend(deps, USER, body(request({ kind: "intro", location: undefined, recipients: one })));
  check(sent.length === 3 && statuses(fourth) === "rejected", "test cap: a 4th test-type message to one number is rejected");
  check(sent[0].body.startsWith("WHOOSH TEST:"), "test kind uses the test template");
}

// 8. Burst limit: 10 requests a minute, then 429 with Retry-After; recovers after a minute.
{
  const { deps } = setup();
  let last;
  for (let i = 0; i < 11; i += 1) last = await handleSend(deps, USER, body(request({ kind: "test", location: undefined })));
  check(last?.status === 429 && last.body.scope === "burst" && last.headers?.["Retry-After"] === "60", "burst: the 11th request in a minute is 429 with Retry-After");
  advance(61);
  const later = await handleSend(deps, USER, body(request({ kind: "test", location: undefined })));
  check(later.status === 200, "burst: allowed again after a minute");
}

// 9. Provider rejection maps the error code; a lost response is retried once, not more.
{
  const { deps } = setup(async () => ({ ok: false, sid: null, status: "rejected", providerErrorCode: 21608 }));
  const reply = await handleSend(deps, USER, body(request()));
  const r = (reply.body.recipients as { status: string; errorCode: string; providerErrorCode: number }[])[0];
  check(r.status === "rejected" && r.errorCode === "trial_recipient_unverified" && r.providerErrorCode === 21608, "provider 21608 -> rejected / trial_recipient_unverified");
}
{
  let calls = 0;
  const { deps } = setup(async () => {
    calls += 1;
    throw new Error("timeout");
  });
  const r = request({ recipients: [{ recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" }] });
  await handleSend(deps, USER, body(r));
  await handleSend(deps, USER, body(r));
  await handleSend(deps, USER, body(r));
  check(calls === 2, `unknown outcome: one re-attempt at most (provider called ${calls} times)`);
}

// 10. Status endpoint and callbacks: monotonic, sticky, signature required.
{
  const { deps, store } = setup();
  const r = request();
  await handleSend(deps, USER, body(r));
  const token = "auth-token";
  const url = "https://ref.supabase.co/functions/v1/sms-status-callback";
  const callback = async (params: Record<string, string>, sign = true) =>
    handleCallback(deps, token, url, params, sign ? await twilioSignature(token, url, params) : "bad");
  const forged = await callback({ MessageSid: "SM1", MessageStatus: "delivered" }, false);
  check(forged.status === 403 && store.deliveries[0].status === "queued", "callback: a bad signature is 403 and changes nothing");
  await callback({ MessageSid: "SM1", MessageStatus: "sent" });
  await callback({ MessageSid: "SM1", MessageStatus: "delivered" });
  await callback({ MessageSid: "SM1", MessageStatus: "sent" });
  await callback({ MessageSid: "SM1", MessageStatus: "failed", ErrorCode: "30003" });
  check(store.deliveries[0].status === "delivered", "callback: delivered sticks through late and conflicting callbacks");
  await callback({ MessageSid: "SM2", MessageStatus: "undelivered", ErrorCode: "30006" });
  check(store.deliveries[1].status === "undelivered" && store.deliveries[1].whooshErrorCode === "recipient_landline", "callback: undelivered with 30006 -> recipient_landline");
  const unknown = await callback({ MessageSid: "SM999", MessageStatus: "delivered" });
  check(unknown.status === 200, "callback: unknown sid is acknowledged with 200");

  const status = await handleStatus(deps, USER, r.crashEventId as string, null);
  check(status.status === 200 && statuses(status) === "delivered,undelivered", `status: reports current statuses (${statuses(status)})`);
  const notMine = await handleStatus(deps, OTHER, r.crashEventId as string, null);
  check(notMine.status === 404, "status: another user's event is 404");
}

// 11. Delete: refused for events under an hour old, allowed after.
{
  const { deps, store } = setup();
  const r = request();
  await handleSend(deps, USER, body(r));
  const early = await handleDelete(deps, USER, body({ crashEventId: r.crashEventId }));
  check(early.status === 409 && early.body.code === "too_recent", "delete: under 1 hour old is 409 too_recent");
  advance(3601);
  const later = await handleDelete(deps, USER, body({ all: true }));
  check(later.status === 200 && later.body.deleted === 1 && store.deliveries.length === 0, "delete: after an hour it deletes the event and its deliveries");
  const bad = await handleDelete(deps, USER, body({ all: true, extra: 1 }));
  check(bad.status === 400, "delete: extra fields are rejected");
}

console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
if (failures > 0) throw new Error(`${failures} checks failed`);
