// Checks for the shared crash-alert modules against the contract's golden cases (Appendix A).
// Run from the repo root:  node supabase/functions/_shared/check.ts   (Node 23.6+)
// Also runs under Deno:     deno run supabase/functions/_shared/check.ts
import {
  delayClause,
  formatAge,
  formatOffset,
  isGsm7,
  render,
  segmentCount,
  type RenderInput,
} from "./template.ts";
import { isNanpE164, normalizeLabel, validateSendRequest, type ValidationLimits } from "./validate.ts";
import {
  mapProviderError,
  mapProviderStatus,
  recipientHash,
  timingSafeEqual,
  twilioSignature,
  verifyTwilioSignature,
} from "./provider.ts";

let failures = 0;
function check(ok: boolean, name: string, detail = ""): void {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok || !detail ? "" : `\n      ${detail}`}`);
  if (!ok) failures += 1;
}

// ---------- Appendix A.2 golden cases, copied verbatim from the contract ----------

const G1 = `WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location (+/-12 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G2 = `WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Last known location (45 s old, +/-30 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G3 = `WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location unavailable.
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G4 = `WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 17 min.
Last known location (45 s old, +/-30 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G5 = `WHOOSH ALERT: Abcdefghij Klmnopqrs may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Mon Dec 28, 11:59 PM (UTC+5:30). Message delayed by 29 min.
Last known location (9 min old, +/-499 m):
Apple Maps: https://maps.apple.com/?ll=-42.36012,-171.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=-42.36012,-171.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G6 = `WHOOSH DEMO - NOT REAL: Alex is demonstrating Whoosh crash alerts. No crash happened.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location (+/-12 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G7 = `WHOOSH TEST: This is a test message from Alex. No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;

const G8 = `WHOOSH: Alex added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out.`;

const G9 = `WHOOSH UPDATE: Alex says they are OK. Please ignore the crash alert sent at Sat Oct 24, 1:41 PM (UTC-4). Sent by Whoosh, not an emergency service. Reply STOP to opt out.`;

const base = { riderLabel: "Alex", detectedAt: "2026-10-24T17:41:07Z", utcOffsetMinutes: -240, delayedSeconds: 0 };
const current = { status: "current" as const, latitude: 42.36012, longitude: -71.05888, accuracyMeters: 12, ageSeconds: 0 };
const lastKnown = { status: "last_known" as const, latitude: 42.36012, longitude: -71.05888, accuracyMeters: 30, ageSeconds: 45 };

const golden: [string, RenderInput, string, number, number][] = [
  ["G1 crash_alert, current", { ...base, kind: "crash_alert", location: current }, G1, 465, 4],
  ["G2 crash_alert, last known", { ...base, kind: "crash_alert", location: lastKnown }, G2, 486, 4],
  ["G3 crash_alert, unavailable", { ...base, kind: "crash_alert", location: { status: "unavailable" } }, G3, 321, 3],
  ["G4 crash_alert, delayed", { ...base, kind: "crash_alert", location: lastKnown, delayedSeconds: 1020 }, G4, 514, 4],
  [
    "G5 worst case",
    {
      kind: "crash_alert",
      riderLabel: "Abcdefghij Klmnopqrs",
      detectedAt: "2026-12-28T18:29:00Z",
      utcOffsetMinutes: 330,
      delayedSeconds: 1740,
      location: { status: "last_known", latitude: -42.36012, longitude: -171.05888, accuracyMeters: 499, ageSeconds: 540 },
    },
    G5,
    540,
    4,
  ],
  ["G6 drill", { ...base, kind: "drill", location: current }, G6, 350, 3],
  ["G7 test", { ...base, kind: "test" }, G7, 180, 2],
  ["G8 intro", { ...base, kind: "intro" }, G8, 186, 2],
  ["G9 all_clear", { ...base, kind: "all_clear" }, G9, 169, 2],
];

for (const [name, input, expected, chars, segments] of golden) {
  const out = render(input);
  check(out === expected, `${name}: matches the contract text`, firstDiff(out, expected));
  check(out.length === chars, `${name}: ${chars} characters (got ${out.length})`);
  check(segmentCount(out) === segments, `${name}: ${segments} segments (got ${segmentCount(out)})`);
  check(isGsm7(out), `${name}: GSM-7 only`);
}

function firstDiff(a: string, b: string): string {
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
    if (a[i] !== b[i]) return `first difference at ${i}: got ${JSON.stringify(a.slice(i, i + 30))}, want ${JSON.stringify(b.slice(i, i + 30))}`;
  }
  return "";
}

// ---------- Appendix A.3 additional cases ----------

const offsets: [number, string][] = [[-570, "UTC-9:30"], [-240, "UTC-4"], [0, "UTC+0"], [330, "UTC+5:30"], [345, "UTC+5:45"]];
for (const [minutes, want] of offsets) check(formatOffset(minutes) === want, `offset ${minutes} -> ${want} (got ${formatOffset(minutes)})`);

// "current" for ages <= 10 s; otherwise the age text.
const ages: [number, string][] = [
  [0, "current"], [9, "current"], [10, "current"], [11, "11 s old"], [59, "59 s old"],
  [60, "1 min old"], [119, "1 min old"], [3599, "59 min old"], [3600, "1 h old"],
];
for (const [seconds, want] of ages) {
  const out = render({ ...base, kind: "crash_alert", location: { ...current, ageSeconds: seconds } });
  const line = out.split("\n")[2];
  const got = line.startsWith("Location (") ? "current" : (/\(([^,]+),/.exec(line)?.[1] ?? line);
  check(got === want, `age ${seconds} s -> ${want} (got ${got})`);
  if (want !== "current") check(formatAge(seconds) === want, `formatAge(${seconds}) = ${want}`);
}

const delays: [number, string][] = [[0, ""], [59, ""], [60, "1 min"], [119, "1 min"], [120, "2 min"]];
for (const [seconds, want] of delays) {
  const got = delayClause(seconds);
  check(want === "" ? got === "" : got === `. Message delayed by ${want}.`, `delay ${seconds} s -> ${want || "none"}`);
}

check(normalizeLabel("  Al   ex  ") === "Al ex", "label whitespace is collapsed");
check(render({ ...base, kind: "crash_alert", location: { ...current, accuracyMeters: 0.2 } }).includes("+/-1 m"), "accuracy rounds to at least 1 m");

// Cap fallback: a long label is impossible (20 chars max), so test the rule with a synthetic input.
{
  // G1 is 465 characters with a 4-character label; a 200-character label makes it 661.
  const long = render({ ...base, kind: "crash_alert", riderLabel: "x".repeat(200), location: current });
  check(!long.includes("Google Maps:") && long.includes("Apple Maps:") && long.length <= 612,
    `over 612 chars, the Google Maps line is dropped first (${long.length} chars)`);
}

// ---------- Validation (contract 5.3) ----------

const limits: ValidationLimits = { supportedTemplateVersions: [1], minConsentVersion: 1, minSchemaVersion: 1, maxRecipients: 3 };
const now = new Date("2026-10-24T17:45:00Z");
const valid = {
  schemaVersion: 1,
  templateVersion: 1,
  crashEventId: "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11",
  kind: "crash_alert",
  riderLabel: "Alex",
  detectedAt: "2026-10-24T17:41:07Z",
  utcOffsetMinutes: -240,
  delayedSeconds: 0,
  location: { status: "current", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 12, ageSeconds: 0 },
  recipients: [
    { recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" },
    { recipientRef: "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f", e164: "+16175550124" },
  ],
  consent: { version: 1, acceptedAt: "2026-10-20T14:02:11Z" },
  appVersion: "1.0 (42)",
};
const code = (body: unknown) => {
  const r = validateSendRequest(body, limits, now);
  return r.ok ? "ok" : `${r.status} ${r.code}`;
};
const withField = (patch: Record<string, unknown>) => ({ ...valid, ...patch });

check(code(valid) === "ok", "the contract's example request is valid");
const cases: [string, unknown, string][] = [
  ["unknown top-level field", withField({ extra: 1 }), "400 invalid_request"],
  ["future schema version", withField({ schemaVersion: 2 }), "403 client_upgrade_required"],
  ["unsupported template", withField({ templateVersion: 9 }), "422 unsupported_template_version"],
  ["old consent version", withField({ consent: { version: 0, acceptedAt: "2026-10-20T14:02:11Z" } }), "403 client_upgrade_required"],
  ["bad crashEventId", withField({ crashEventId: "nope" }), "400 invalid_request"],
  ["uppercase uuid", withField({ crashEventId: valid.crashEventId.toUpperCase() }), "400 invalid_request"],
  ["unknown kind", withField({ kind: "panic" }), "400 invalid_request"],
  ["label with emoji", withField({ riderLabel: "Alex 🚲" }), "400 invalid_label"],
  ["label too long", withField({ riderLabel: "x".repeat(21) }), "400 invalid_label"],
  ["detected 6 min in the future", withField({ detectedAt: "2026-10-24T17:51:01Z" }), "400 invalid_request"],
  ["crash 61 min old", withField({ detectedAt: "2026-10-24T16:43:59Z" }), "422 event_too_old"],
  ["offset out of range", withField({ utcOffsetMinutes: 900 }), "400 invalid_request"],
  ["delay out of range", withField({ delayedSeconds: 90_000 }), "400 invalid_request"],
  ["crash without location", withField({ location: undefined }), "400 invalid_location"],
  ["latitude out of range", withField({ location: { ...valid.location, latitude: 91 } }), "400 invalid_location"],
  ["6 decimals", withField({ location: { ...valid.location, latitude: 42.360121 } }), "400 invalid_location"],
  ["unavailable with coordinates", withField({ location: { status: "unavailable", latitude: 1 } }), "400 invalid_location"],
  ["test with a location", withField({ kind: "test" }), "400 invalid_location"],
  ["no recipients", withField({ recipients: [] }), "400 invalid_recipient"],
  ["four recipients", withField({ recipients: [1, 2, 3, 4].map((i) => ({ recipientRef: `00000000-0000-4000-8000-00000000000${i}`, e164: `+1617555012${i}` })) }), "422 too_many_recipients"],
  ["duplicate number", withField({ recipients: [valid.recipients[0], { ...valid.recipients[1], e164: "+16175550123" }] }), "400 invalid_recipient"],
  ["non-US number", withField({ recipients: [{ ...valid.recipients[0], e164: "+447700900123" }] }), "400 invalid_recipient"],
];
for (const [name, body, want] of cases) check(code(body) === want, `validation: ${name} -> ${want} (got ${code(body)})`);
check(code({ ...withField({ kind: "test", location: undefined }) }) === "ok", "validation: test without location is valid");
{
  const r = validateSendRequest(withField({ riderLabel: "  Al   ex " }), limits, now);
  check(r.ok && r.request.riderLabel === "Al ex", "validation: label is normalized");
}

check(isNanpE164("+16175550123"), "NANP: 617-555-0123 is valid");
check(!isNanpE164("+11175550123"), "NANP: area code starting with 1 is invalid");
check(!isNanpE164("+16171550123"), "NANP: exchange starting with 1 is invalid");
check(!isNanpE164("+19115550123"), "NANP: N11 area code is invalid");
check(!isNanpE164("+1617555012"), "NANP: 9 digits is invalid");

// ---------- Provider helpers ----------

check(mapProviderStatus("sending") === "queued" && mapProviderStatus("delivered") === "delivered", "status mapping");
check(mapProviderStatus("read") === null, "unknown provider status is ignored");
check(mapProviderError(21610) === "recipient_opted_out" && mapProviderError(12345) === "provider_error", "error mapping");
check(mapProviderError(null) === null, "no error code maps to null");
check(timingSafeEqual("abc", "abc") && !timingSafeEqual("abc", "abd") && !timingSafeEqual("abc", "abcd"), "constant-time compare");

{
  const pepper = "p".repeat(32);
  const h1 = await recipientHash(pepper, "+16175550123");
  const h2 = await recipientHash(pepper, "+16175550123");
  const h3 = await recipientHash("q".repeat(32), "+16175550123");
  check(/^[0-9a-f]{64}$/.test(h1), "recipient hash is 64 hex chars (fits the database check)");
  check(h1 === h2 && h1 !== h3, "recipient hash is stable for one pepper and changes with the pepper");
  let threw = false;
  try {
    await recipientHash("short", "+16175550123");
  } catch {
    threw = true;
  }
  check(threw, "a short pepper is refused");
}

{
  // Known-answer test computed independently (HMAC-SHA1 over url + sorted key/value pairs).
  const token = "12345";
  const url = "https://example.supabase.co/functions/v1/sms-status-callback";
  const params = { MessageSid: "SM123", MessageStatus: "delivered", AccountSid: "AC1" };
  const sig = await twilioSignature(token, url, params);
  const { createHmac } = await import("node:crypto");
  const expected = createHmac("sha1", token).update(`${url}AccountSidAC1MessageSidSM123MessageStatusdelivered`).digest("base64");
  check(sig === expected, "Twilio signature matches an independent HMAC-SHA1 computation");
  check(await verifyTwilioSignature(token, url, params, expected), "a valid signature verifies");
  check(!(await verifyTwilioSignature(token, url, { ...params, MessageStatus: "failed" }, expected)), "a tampered parameter fails");
  check(!(await verifyTwilioSignature(token, url, params, null)), "a missing signature fails");
}

console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
if (failures > 0) throw new Error(`${failures} checks failed`);
