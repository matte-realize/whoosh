# Crash Alert Backend Contract — Whoosh

**Status: DRAFT.** Owned by **Role C** (Backend / Data & Integration). The iOS app implements the
crash-alert notifier (spec `crash-response`, `SupabaseCrashNotifier`) only after this document is
marked **Agreed** by Role C and the iOS owner. Change it through a quick review, then bump the
version. Same spirit as `supabase-contract.md`.

Version: 0.1 (draft, October 24, 2026)

> No backend code lives in this document. It defines behavior, shapes, limits, and tests the two
> sides must agree on. SQL, function code, and provider configuration are Role C's tasks.

**Verification note.** Provider specifics (Twilio is the reference) and Apple specifics below were
written from established knowledge; live documentation could not be consulted while drafting.
Items tagged **Verify** must be checked against current provider/Apple docs before the contract is
marked Agreed.

## 1. Purpose and principles

1. Send a short, fixed-template **SMS to the rider's emergency contacts** on the rider's behalf,
   because an iOS app cannot send an SMS silently from the rider's number.
2. **No open relay.** The backend renders fixed templates from structured fields. It never
   forwards arbitrary client text or URLs.
3. **No provider credentials in the app or the repo.** They exist only as Edge Function secrets.
4. **Data minimization.** The backend never persists plaintext phone numbers, message bodies, or
   coordinates. It persists a keyed hash and the last 2 digits of each number, statuses, and
   timestamps, for a bounded retention period.
5. **Idempotent and bounded.** A single crash event can never produce more than one message per
   recipient per kind. Costs are capped per user, per recipient, and globally, with a kill switch.
6. **Honest.** The service is *best-effort*. It does not guarantee delivery and is not an emergency
   service. The same words appear in every message.
7. **Optional for the app.** The app works fully offline; this service is used only when the rider
   has enabled crash alerts and consented.

## 2. Components

| Component | Type | Auth | Purpose |
| --------- | ---- | ---- | ------- |
| `send-crash-alert` | Supabase Edge Function, `POST` | Supabase JWT (anonymous user) + anon `apikey` | Validate, dedupe, rate-limit, render, and send messages |
| `crash-alert-status` | Edge Function, `GET` | Supabase JWT | Return per-recipient statuses for the caller's event |
| `sms-status-callback` | Edge Function, `POST` (form-encoded) | **No JWT**; provider signature validated | Receive delivery status callbacks from the provider |
| `delete-crash-audit` | Edge Function, `POST` | Supabase JWT | Rider deletes their audit rows (not younger than 1 hour) |
| Database tables | Postgres + RLS | — | See section 9 |
| Config / kill switch | Table `crash_alert_config` + environment flag | service role only | See section 11 |

The function base path is `https://<project-ref>.supabase.co/functions/v1/`. The iOS app learns
the base from the same `SUPABASE_URL` already in `Secrets.xcconfig`.

## 3. Authentication and transport

- TLS only. Plain HTTP is not served.
- The app signs in with **Supabase anonymous auth** (already planned for ride sync) and sends
  `Authorization: Bearer <access_token>` and `apikey: <anon key>` on every call.
- `send-crash-alert`, `crash-alert-status`, and `delete-crash-audit` require a valid JWT; the
  function additionally requires the `is_anonymous` or authenticated role claim and uses
  `auth.uid()` as `user_id`.
- `sms-status-callback` is **not** called by the app. It is called by the provider and protected
  by the provider's request signature (section 7).
- The `service_role` key is used only inside Edge Functions via secrets and never leaves the
  backend.
- **Residual risk:** anonymous accounts are cheap to create, so JWT validity does not prove a
  real device. Controls: fixed templates, per-recipient and global caps, a spend cap, and a kill
  switch. Production hardening (App Attest / DeviceCheck, CAPTCHA) is an explicit follow-up.

## 4. Conventions

- JSON, UTF-8, `Content-Type: application/json` (callback: `application/x-www-form-urlencoded`).
- Timestamps: ISO-8601 UTC with `Z` (for example `2026-10-24T17:41:07Z`).
- UUIDs: lowercase canonical form.
- Phone numbers: **E.164**, **US/Canada only in v1** (`+1` followed by a NANP-valid 10-digit number).
- Request/response include `schemaVersion` (integer, currently `1`). Breaking changes bump it.
- `templateVersion` (integer, currently `1`) selects the message template independently.
- Every response includes `requestId` (opaque) for support correlation; it contains no PII.
- Response time budget: the function replies within **8 s**; the app's client timeout is **10 s**.

## 5. `send-crash-alert`

`POST /functions/v1/send-crash-alert`

### 5.1 Kinds

| `kind` | When | Counts against | Location block | Template |
| ------ | ---- | -------------- | -------------- | -------- |
| `crash_alert` | Countdown expired / Send now / recovery send | Real-alert quota | required | Appendix A (G1–G5) |
| `drill` | "Simulate crash" demo path | Test/drill quota | required (current or last known) | Appendix A (G6) |
| `test` | Rider taps "Send a test" | Test/drill quota | absent | Appendix A (G7) |
| `intro` | New contact introduction | Test/drill quota | absent | Appendix A (G8) |
| `all_clear` | Rider taps "Tell contacts I'm OK" (stretch) | Test/drill quota | absent | Appendix A (G9) |

### 5.2 Request

```json
{
  "schemaVersion": 1,
  "templateVersion": 1,
  "crashEventId": "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11",
  "kind": "crash_alert",
  "riderLabel": "Alex",
  "detectedAt": "2026-10-24T17:41:07Z",
  "utcOffsetMinutes": -240,
  "delayedSeconds": 0,
  "location": {
    "status": "current",
    "latitude": 42.36012,
    "longitude": -71.05888,
    "accuracyMeters": 12,
    "ageSeconds": 0
  },
  "recipients": [
    { "recipientRef": "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", "e164": "+16175550123" },
    { "recipientRef": "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f", "e164": "+16175550124" }
  ],
  "consent": { "version": 1, "acceptedAt": "2026-10-20T14:02:11Z" },
  "appVersion": "1.0 (42)"
}
```

`location.status` is one of `current`, `last_known`, `unavailable`. When `unavailable`, the
`latitude`, `longitude`, `accuracyMeters`, and `ageSeconds` fields must be **absent**.
For `test`, `intro`, and `all_clear`, `location` must be absent. For `all_clear`, `detectedAt`
is the original crash time.

### 5.3 Validation (all failures are non-retryable `400`/`422` unless noted)

| Field | Rule | Error code |
| ----- | ---- | ---------- |
| `schemaVersion` | supported | `client_upgrade_required` (403) |
| `templateVersion` | in `crash_alert_config.supported_template_versions` | `unsupported_template_version` (422) |
| `crashEventId` | UUID | `invalid_request` |
| `kind` | one of the five kinds | `invalid_request` |
| `riderLabel` | 1–20 chars, only letters, digits, space, `.`, `'`, `-` | `invalid_label` |
| `detectedAt` | not more than 5 min in the future; for `crash_alert`/`drill` not older than **60 min** | `invalid_request` / `event_too_old` (422) |
| `utcOffsetMinutes` | integer −720…+840 | `invalid_request` |
| `delayedSeconds` | integer 0…86400 | `invalid_request` |
| `location` | as in 5.2; latitude −90…90, longitude −180…180, `accuracyMeters` 0…9999, `ageSeconds` 0…86400, at most 5 decimals | `invalid_location` |
| `recipients` | 1–3 items, unique `e164`, each `+1` NANP-valid, unique `recipientRef` | `too_many_recipients` (422) / `invalid_recipient` |
| `consent.version` | ≥ `crash_alert_config.min_consent_version` | `client_upgrade_required` (403) |
| body size | ≤ 4 KB | `payload_too_large` (413) |
| unknown fields | rejected | `invalid_request` |

### 5.4 Processing order (normative)

1. Verify JWT; read `user_id`.
2. If the kill switch is on ⇒ `503 service_disabled`.
3. Validate the request (5.3).
4. Compute `recipient_hash` for each recipient (keyed hash, section 9) and `recipient_last2`.
5. **Idempotency:** insert the event row under the unique key (`user_id`, `crash_event_id`,
   `kind`). If it already exists, compare the *immutable* fields (`kind`, `detectedAt`,
   `riderLabel`, `templateVersion`); mismatch ⇒ `409 idempotency_conflict`. Match ⇒ continue to
   per-recipient handling in "dedupe mode" (step 7).
6. **Rate limits and caps** (section 10). A recipient or request over a limit is rejected
   (`429 rate_limited` for the whole request when a per-user cap is hit; per-recipient cap hits
   are reported per recipient with `rejected` / `rate_limited_recipient`).
7. For each recipient: insert the delivery row under the unique key (`event_id`,
   `recipient_hash`). If it exists ⇒ **do not send**; return the stored status
   (`deduplicated: true` for the response if every recipient was a duplicate). If new ⇒ render the
   template, call the provider **once**, store `provider_message_sid` and status `queued`.
8. Return the per-recipient results (section 5.5).

Mutable fields on retries (`location`, `delayedSeconds`, `appVersion`) are ignored for recipients
already sent; they apply only to recipients not yet sent.

### 5.5 Response (`200 OK` — request processed; individual recipients may still be rejected)

```json
{
  "schemaVersion": 1,
  "requestId": "req_01HF...",
  "crashEventId": "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11",
  "kind": "crash_alert",
  "deduplicated": false,
  "recipients": [
    {
      "recipientRef": "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e",
      "status": "queued",
      "errorCode": null,
      "providerErrorCode": null,
      "segments": 4,
      "updatedAt": "2026-10-24T17:41:39Z"
    },
    {
      "recipientRef": "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f",
      "status": "rejected",
      "errorCode": "trial_recipient_unverified",
      "providerErrorCode": 21608,
      "segments": 0,
      "updatedAt": "2026-10-24T17:41:39Z"
    }
  ],
  "limits": { "realAlertsRemaining24h": 4, "testMessagesRemaining24h": 10 },
  "serverTime": "2026-10-24T17:41:39Z"
}
```

### 5.6 Recipient `status` values

| Status | Meaning | Terminal |
| ------ | ------- | -------- |
| `queued` | Accepted by the backend and handed to the provider; not yet confirmed sent | no |
| `sent` | The provider handed the message to the carrier | no |
| `delivered` | The carrier confirmed delivery to the handset (best-effort; not all carriers report) | yes |
| `undelivered` | The carrier could not deliver (see error code) | yes |
| `failed` | The provider could not send (see error code) | yes |
| `rejected` | Whoosh refused this recipient before the provider (validation, cap, trial restriction) | yes |

Ordering rule: `queued` < `sent` < {`delivered`, `undelivered`, `failed`, `rejected`}. Statuses
**never regress**. A terminal status is **sticky**; a later conflicting terminal status is logged
(counter only) and not applied.

## 6. `crash-alert-status`

`GET /functions/v1/crash-alert-status?crashEventId=<uuid>&kind=crash_alert`

- Auth: JWT. Returns only rows where `user_id = auth.uid()` (RLS).
- `kind` defaults to `crash_alert`.
- `200`: same body as 5.5 (without `deduplicated`), with the current status per recipient.
- `404 unknown_event` when no such event exists for the caller.
- Rate limit: 60 requests/min/user (burst 10); `429 rate_limited` (`scope: "burst"`) with
  `Retry-After`.
- The app calls it per section "Delivery recording and polling" of the design (5 s for 60 s, then
  15 s up to 10 min, foreground only).

## 7. `sms-status-callback` (provider → backend)

`POST /functions/v1/sms-status-callback` — `application/x-www-form-urlencoded`.

- The provider is told this URL per message (`StatusCallback`).
- **Validate the provider signature** (Twilio: the `X-Twilio-Signature` header, an HMAC over the
  full request URL plus sorted POST parameters using the account auth token; compare in constant
  time). Invalid signature ⇒ `403` and no state change. **Verify** current algorithm details.
- Fields used: `MessageSid`, `MessageStatus`, `ErrorCode` (if present). Everything else ignored.
- Lookup by `provider_message_sid`. Unknown sid ⇒ `200` (acknowledge, ignore, count).
- Apply the monotonic/sticky rules from 5.6. **Idempotent:** duplicate and out-of-order
  callbacks are expected.
- Always respond `200` quickly (< 5 s) after a valid signature, so the provider does not retry
  storms.
- Status mapping (Twilio example — **Verify**):

| Provider `MessageStatus` | Whoosh `status` |
| ------------------------ | --------------- |
| `accepted`, `queued`, `sending` | `queued` |
| `sent` | `sent` |
| `delivered` | `delivered` |
| `undelivered` | `undelivered` |
| `failed` | `failed` |
| anything else | ignored (logged) |

- Provider error-code mapping to Whoosh `errorCode` (Twilio example — **Verify** against the
  current Twilio error-code reference):

| Provider code | Whoosh `errorCode` | Rider-facing meaning |
| ------------- | ------------------ | -------------------- |
| 21610 | `recipient_opted_out` | The contact replied STOP |
| 21211, 21614 | `recipient_invalid` | The number can't receive texts |
| 30003, 30005 | `recipient_unreachable` | Phone off/out of coverage/unknown handset |
| 30006 | `recipient_landline` | The number looks like a landline |
| 30007 | `carrier_filtered` | The carrier blocked the message |
| 21608 | `trial_recipient_unverified` | Demo/trial account: number not verified |
| 21408 | `region_not_enabled` | Sending region not enabled |
| other | `provider_error` | Message couldn't be delivered |

## 8. `delete-crash-audit`

`POST /functions/v1/delete-crash-audit` with `{ "crashEventId": "<uuid>" }` or `{ "all": true }`.

- Deletes the caller's event and delivery rows (cascade). Refuses events younger than **1 hour**
  (`409 too_recent`) so a mid-incident delete cannot reset deduplication.
- Does not delete `crash_alert_counters` (no PII; short TTL, section 9).
- `200 { "deleted": N }`.

## 9. Data model

All tables have Row Level Security enabled. Clients never insert, update, or delete these tables
directly; writes occur in Edge Functions with the service role. Clients may `select` their own
rows only (`user_id = auth.uid()`). No table stores plaintext phone numbers, message bodies, or
coordinates.

### `crash_alert_events`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | internal |
| `user_id` | uuid | `auth.uid()` of the caller; references `auth.users` |
| `crash_event_id` | uuid | client-generated idempotency key |
| `kind` | text | `crash_alert` \| `drill` \| `test` \| `intro` \| `all_clear` |
| `template_version` | int | |
| `consent_version` | int | |
| `detected_at` | timestamptz | |
| `delayed_seconds` | int | |
| `location_status` | text | `current` \| `last_known` \| `unavailable` \| `none` — **status only, no coordinates** |
| `app_version` | text | |
| `created_at` | timestamptz | `default now()` |

Unique: (`user_id`, `crash_event_id`, `kind`).

### `crash_alert_deliveries`

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `event_id` | uuid FK | references `crash_alert_events.id`, `on delete cascade` |
| `user_id` | uuid | |
| `recipient_ref` | uuid | client-generated contact UUID (not PII) |
| `recipient_hash` | text | **keyed hash (HMAC-SHA-256 with a server-side pepper secret)** of the E.164 number, hex. A per-row salt would defeat cross-row rate limiting, so a *keyed* hash is used; treat it as personal data because the 10-digit space is small if the pepper leaks |
| `recipient_last2` | text(2) | last two digits, for audit display |
| `provider` | text | e.g. `twilio` |
| `provider_message_sid` | text null, unique | |
| `status` | text | per 5.6 |
| `whoosh_error_code` | text null | |
| `provider_error_code` | int null | |
| `segments` | int | for cost audit |
| `attempt_count` | int | provider calls made for this row (expected 1) |
| `created_at`, `updated_at`, `terminal_at` | timestamptz | |

Unique: (`event_id`, `recipient_hash`).

### `crash_alert_counters` (rate limiting; no PII beyond the keyed hash)

| Column | Type | Notes |
| ------ | ---- | ----- |
| `id` | uuid PK | |
| `user_id` | uuid | |
| `bucket` | text | `real_alert` \| `test_message` \| `new_recipient` \| `recipient_real` \| `recipient_test` \| `burst` |
| `recipient_hash` | text null | for recipient-scoped buckets |
| `created_at` | timestamptz | rolling-window counting |

TTL: rows older than **48 hours** are purged.

### `crash_alert_config` (single row; service role only — **no** client access)

`enabled` (kill switch), `min_consent_version`, `supported_template_versions`,
`min_schema_version`, `trial_mode` (bool), and the numeric limits in section 10 so limits can be
tuned without a deploy.

### RLS summary

| Table | Client `select` | Client write |
| ----- | --------------- | ------------ |
| `crash_alert_events` | own rows | none (functions only) |
| `crash_alert_deliveries` | own rows | none |
| `crash_alert_counters` | none | none |
| `crash_alert_config` | none | none |

### Retention

| Data | Retention |
| ---- | --------- |
| Events + deliveries (audit) | **30 days**, then purged by a scheduled job; rider may delete earlier (section 8) |
| Counters | 48 hours |
| Logs | 14 days, PII-free |
| Provider-side message logs/bodies | **Verify and document** the provider's retention; minimize or redact where the provider allows |

## 10. Rate limits and cost controls

Defaults (tunable in `crash_alert_config`). Exceeding a limit returns `429 rate_limited` with
`scope`, `retryAfterSeconds` when applicable, and `retryable: false` for daily scopes.

| Scope | Limit (rolling 24 h unless noted) | Notes |
| ----- | --------------------------------- | ----- |
| Recipients per request | 3 | `422 too_many_recipients` |
| Real alerts per user (`crash_alert` events) | 5 | each event ≤ 3 recipients |
| Test/intro/drill/all-clear messages per user | 10 | |
| Test-type messages per recipient (per user) | 3 | `intro` + `test` + `drill` |
| New distinct recipients per user | 5 | protects third parties |
| Messages per recipient hash across **all** users | 5 real + 3 test-type | stops one victim being spammed |
| Requests per user (burst) | 10 per minute on `send-crash-alert` | `Retry-After` honored once by the client |
| Global | 200 messages per hour | spend guard |
| Segments per message | ≤ 4 (612 GSM-7 chars) | longer renders are rejected server-side |

Additional controls:

- **Fixed templates only;** `riderLabel` is the only free text and is charset-restricted.
- **Kill switch** (section 11).
- **Provider spend cap / usage alerts**, auto-recharge disabled, geographic permissions limited to
  US/CA, and (where supported) per-message price and validity-period limits so a queued message
  does not deliver hours late (**Verify**: Twilio `ValidityPeriod` / `MaxPrice`).
- **Cost model:** cost ≈ segments × recipients × per-segment provider price. Use the provider's
  pricing page for estimates; this contract does not quote prices.
- Logging without PII (section 12).

## 11. Kill switch and trial mode

- `crash_alert_config.enabled = false` (or an environment flag) ⇒ `send-crash-alert` immediately
  returns `503 service_disabled` with `retryable: false`. The app then goes straight to the
  composer fallback. `crash-alert-status` keeps working.
- `trial_mode = true` documents that the provider account is a trial: only verified recipient
  numbers can receive messages, and the provider prefixes message bodies (which can add
  segments). Trial rejections surface as `trial_recipient_unverified`.
- Role C must rehearse the kill switch before the demo.

## 12. Security, logging, and secrets

- **Secrets (names only; values never in Git or the app):** provider account identifier, provider
  credential, sender number or messaging-service identifier, the recipient-hash pepper, and the
  callback base URL. They live in Edge Function secrets in Role C's environment.
- Logs may contain: `requestId`, `user_id`, `crash_event_id`, `kind`, statuses, error codes,
  counts, and timings. Logs must **not** contain: phone numbers (full or partial), labels,
  coordinates, message bodies, tokens, or provider credentials.
- Input hardening: strict schema, size limit, constant-time signature comparison, no reflection of
  input in error messages.
- The callback function must reject unsigned/invalid requests before touching the database.
- Dependency and secret scanning should run on the functions repo.

## 13. What each side can rely on

**The app relies on:**

- A repeated request with the same (`crashEventId`, `kind`) never sends a second message to the
  same recipient.
- Statuses are monotonic and terminal statuses are sticky.
- Error bodies carry a stable `code` and a `retryable` flag.

**The backend relies on:**

- The app sends the request only after consent and after the rider's countdown expired or the
  rider tapped Send now (the app is the only party that knows).
- The app never sends footage, ride data, or arbitrary text (the schema has no field for it).
- The same `crashEventId` is reused for retries of one event.

### Client behavior per outcome (normative; mirrors requirements 12.5/12.6)

| Outcome | Client behavior |
| ------- | --------------- |
| `200`, ≥ 1 recipient `queued`/`sent`/`delivered` | Event `sent`; poll status |
| `200`, all recipients `rejected` with non-retryable code | Event `failed` → composer fallback |
| `401 unauthenticated` | Refresh the session once and retry; then retryable |
| `403 client_upgrade_required`, `422 unsupported_template_version` | No retry; composer fallback; ask to update the app |
| `409 idempotency_conflict` | No retry; log; composer fallback |
| `429 rate_limited` daily scopes | No retry; composer fallback with the reason |
| `429 rate_limited` burst | Wait `Retry-After` once, then retry |
| `503 service_disabled` | No retry; composer fallback |
| `500`, `502`, `504`, timeout, no connection | Retry with backoff using the same `crashEventId` |
| Unknown code | Retry once, then fail |

**Unknown-outcome policy (timeouts, `504`).** The backend inserts the delivery row *before* the
provider call, so a retry for a row that has a `provider_message_sid` is a no-op. A row with **no
sid** after the request was lost may be re-attempted once by the retry (the row's `attempt_count`
becomes 2). The trade-off — a rare duplicate over a silent loss — is the owner's decision (design
O5). The provider call should carry the provider's own idempotency header where it exists
(**Verify**).

## 14. Open items for Role C

- [ ] Review this draft; mark **Agreed** and set version 1.0 (with the iOS owner).
- [ ] Confirm provider (Twilio vs. alternative) and who owns the account/billing (design O6).
- [ ] Create the provider trial account; verify the demo recipient numbers; set spend cap, usage
      alerts, and geographic permissions (US/CA).
- [ ] Decide `ValidityPeriod` / `MaxPrice` usage and provider message-log retention/redaction.
- [ ] Choose the hashing pepper rotation approach (rotation invalidates counters, acceptable).
- [ ] Confirm migration plan, scheduled purge job, and the config table defaults.
- [ ] Provide a test environment (or staging project) and a way to flip the kill switch.
- [ ] Production: sender registration (10DLC or toll-free verification) with lead time;
      App Attest/DeviceCheck; recipient opt-out sync; provider DPA.

---

## Appendix A — Message template v1 and golden cases

These strings are the **single source of truth** for the iOS `CrashMessageBuilder` golden tests
and the backend renderer tests. Both sides copy them verbatim into their test suites. Lines are
separated by a single LF. The text is **ASCII / GSM-7 only**. Counts below were computed with
a GSM-7 basic-set check and the segment rule "≤ 160 ⇒ 1, else ceil(n / 153)".

### A.1 Formatting rules

| Item | Rule |
| ---- | ---- |
| Locale | Fixed, locale-independent English; 12-hour clock; abbreviations `Sun Mon Tue Wed Thu Fri Sat`, `Jan … Dec` |
| Local time | Detection time shifted by `utcOffsetMinutes`: `Sat Oct 24, 1:41 PM` |
| Offset | `UTC` + sign + hours, plus `:mm` only when minutes ≠ 0: `UTC-4`, `UTC+5:30`, `UTC+0` |
| Delay clause | Appended to the Time line when `delayedSeconds` ≥ 60: `. Message delayed by N min.` where N = floor(seconds / 60) |
| Location, `current` (age ≤ 10 s) | `Location (+/-A m):` then the two link lines |
| Location, `last_known` | `Last known location (<age>, +/-A m):` then the two link lines |
| Location, `unavailable` | `Location unavailable.` (no links) |
| Age | < 60 s: `N s old`; 60–3599 s: `N min old` (floor); ≥ 3600 s: `N h old` (floor) |
| Accuracy `A` | round to the nearest whole meter, minimum 1 |
| Coordinates | exactly 5 decimal places, `.` separator, leading `-` for negatives |
| Apple Maps link | `https://maps.apple.com/?ll=<lat>,<lon>&q=Rider` (**Verify** current Apple Maps URL scheme) |
| Google Maps link | `https://www.google.com/maps/search/?api=1&query=<lat>,<lon>` (**Verify** current Google Maps URL scheme) |
| Rider label | sanitized to GSM-7-safe charset, whitespace collapsed, 1–20 chars |
| Length cap | `crash_alert`/`drill` ≤ 612 characters (4 segments); if exceeded, drop the `Google Maps:` line first |

### A.2 Golden cases

**G1 — `crash_alert`, current fix** (465 chars, 4 segments).
Inputs: label `Alex`; detected 2026-10-24T17:41:07Z; offset −240; delayed 0; location current
42.36012, −71.05888, accuracy 12, age 0.

```
WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location (+/-12 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G2 — `crash_alert`, last known** (486 chars, 4 segments).
Inputs: as G1 but location `last_known`, accuracy 30, age 45 s.

```
WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Last known location (45 s old, +/-30 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G3 — `crash_alert`, location unavailable** (321 chars, 3 segments).
Inputs: as G1 but location `unavailable`.

```
WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location unavailable.
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G4 — `crash_alert`, delayed (queued offline)** (514 chars, 4 segments).
Inputs: as G2 plus `delayedSeconds` 1020 (17 min).

```
WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 17 min.
Last known location (45 s old, +/-30 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G5 — worst case** (540 chars, 4 segments).
Inputs: label `Abcdefghij Klmnopqrs` (20 chars); detected 2026-12-28T18:29:00Z; offset +330; location
`last_known` −42.36012, −171.05888, accuracy 499, age 540 s; delayed 1740 s.

```
WHOOSH ALERT: Abcdefghij Klmnopqrs may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.
Time: Mon Dec 28, 11:59 PM (UTC+5:30). Message delayed by 29 min.
Last known location (9 min old, +/-499 m):
Apple Maps: https://maps.apple.com/?ll=-42.36012,-171.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=-42.36012,-171.05888
Please try to reach them. If you can't, consider calling emergency services.
Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G6 — `drill`** (350 chars, 3 segments). Inputs: as G1 with kind `drill`.

```
WHOOSH DEMO - NOT REAL: Alex is demonstrating Whoosh crash alerts. No crash happened.
Time: Sat Oct 24, 1:41 PM (UTC-4)
Location (+/-12 m):
Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider
Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888
Sent by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G7 — `test`** (180 chars, 2 segments). Inputs: label `Alex`.

```
WHOOSH TEST: This is a test message from Alex. No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out.
```

**G8 — `intro`** (186 chars, 2 segments). Inputs: label `Alex`.

```
WHOOSH: Alex added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out.
```

**G9 — `all_clear`** (169 chars, 2 segments). Inputs: label `Alex`; original detected time as G1.

```
WHOOSH UPDATE: Alex says they are OK. Please ignore the crash alert sent at Sat Oct 24, 1:41 PM (UTC-4). Sent by Whoosh, not an emergency service. Reply STOP to opt out.
```

### A.3 Additional cases both sides must implement (expected output derived from the rules)

| Case | Input | Expected |
| ---- | ----- | -------- |
| Offset formatting | −570, −240, 0, +330, +345 | `UTC-9:30`, `UTC-4`, `UTC+0`, `UTC+5:30`, `UTC+5:45` |
| Age formatting | 0, 9, 10, 11, 59, 60, 119, 3599, 3600 | `current` (≤ 10 s), `current`, `current`, `11 s old`, `59 s old`, `1 min old`, `1 min old`, `59 min old`, `1 h old` |
| Delay clause | 0, 59, 60, 119, 120 | none, none, `1 min`, `1 min`, `2 min` |
| Label sanitization | `Álex ”A”` | non-GSM characters replaced/stripped, whitespace collapsed (exact mapping table lives with the builder tests) |
| Cap fallback | A rendering > 612 chars | drop the `Google Maps:` line first |
| Trial prefix (backend only) | provider prepends text | segment counts in logs may exceed the template count; not an error |

### A.4 Template change process

Any change to wording bumps `templateVersion`, updates this appendix, and both test suites in the
same PR window. The backend keeps rendering older supported versions until the minimum app version
moves.
