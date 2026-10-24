# Whoosh crash-alert backend (Supabase Edge Functions)

Backend for the opt-in **automatic crash-alert SMS** feature. When a rider's countdown expires
(or they tap "Send now"), the iOS app calls this backend, which renders a fixed-template message
and sends it to the rider's emergency contacts through Twilio. An iOS app cannot send an SMS
silently from the rider's number, so this relay exists — but it is a **closed relay**: it renders
fixed templates from structured fields and never forwards arbitrary client text.

> **Contract status.** This implements `.kiro/team/crash-alert-contract.md`, which is **DRAFT 0.1,
> drafted by the iOS owner for Role C to review.** Role C owns the schema, functions, and provider
> config. Before relying on this in production, Role C should review the contract, resolve the
> §14 open items, mark it **Agreed (v1.0)**, and re-check every item tagged **Verify** against
> current Twilio / Apple Maps / Google Maps documentation (the provider error-code table, the
> `X-Twilio-Signature` algorithm, the Messages API fields, and the map URL schemes were written
> from established knowledge without live docs). The golden message tests pin the exact wording.

## What's here

```
supabase/
  migrations/20261024150000_crash_alerts.sql   Tables, RLS, grants, indexes, purge function (C3)
  functions/
    _shared/        message.ts (Appendix A renderer), validation.ts (§5.3), hash.ts (keyed HMAC),
                    twilio.ts (REST send + signature + status/error maps), env.ts, http.ts, limits.ts
    send-crash-alert/index.ts     Validate, dedupe, rate-limit, render, send (C4/C7/C11)
    sms-status-callback/index.ts  Twilio signature + monotonic/sticky status updates (C5)
    crash-alert-status/index.ts   Per-user status read (C6)
    tests/          Deno unit tests: golden messages G1-G9 + A.3, validation matrix, Twilio
                    status/error maps, monotonic status, signature vector, recipient hash
    .env.example    Secret NAMES only — never real values
    deno.json       Import map + `deno task test`
```

Not implemented here (future / out of this task's scope): `delete-crash-audit` (contract §8) and
the scheduled purge job wiring (the `purge_crash_alert_data()` function exists; schedule it with
pg_cron per the comment at the end of the migration).

## Privacy invariants (enforced in code)

- **No plaintext PII at rest.** The DB stores only a keyed HMAC of each number
  (`RECIPIENT_HASH_PEPPER`) plus its last 2 digits, statuses, and timestamps. No phone numbers,
  no message bodies, no coordinates (`location_status` is a status word only).
- **Credentials never in Git or the app.** Twilio creds, the pepper, and the service-role key live
  only as Edge Function secrets. `.env` is gitignored; only `.env.example` (names) is committed.
- **Logs are PII-free** (contract §12): requestId, user_id, crash_event_id, kind, statuses, error
  codes, counts — never numbers, labels, coordinates, or bodies.
- **Closed relay**: `riderLabel` is the only free text and is charset-restricted and length-capped.

## Prerequisites

- The Supabase CLI (`supabase`) logged in and linked to the project: `supabase link --project-ref <ref>`.
- Deno (bundled with the Supabase CLI runtime) for running the tests locally.

## Deploy — step by step (owner / Role C)

### 1. Twilio trial account and verified numbers

1. Create a free **Twilio trial** account at https://www.twilio.com/try-twilio.
2. From the Twilio Console copy the **Account SID** and **Auth Token**.
3. Get a trial **phone number** (Console → Phone Numbers → Buy a number, SMS-capable, US/CA).
4. **Verify every demo recipient number** (trial accounts can only text verified numbers):
   Console → Phone Numbers → Verified Caller IDs → add each teammate's phone and confirm the code.
   Unverified recipients come back as `trial_recipient_unverified` (Twilio code 21608), which the
   app surfaces as a clear status — expected on trial.
5. Set **Geo Permissions** to US/CA only, set a **spend cap / usage alert**, and turn **auto-recharge
   off** (Console → Billing). These are part of the abuse controls in contract §10.
6. (Production only, long lead time) register the sender via **10DLC** or **toll-free verification**;
   trial is fine for the demo.

### 2. Database migration

```sh
supabase db push
```

This applies `20261024150000_crash_alerts.sql`: the four `crash_alert_*` tables with RLS (clients
read only their own rows; counters/config have no client access), service-role grants, indexes, and
`purge_crash_alert_data()`.

Verify RLS quickly (contract C3 acceptance): sign in as two different anonymous users and confirm
neither can `select` the other's `crash_alert_events` / `crash_alert_deliveries` rows, and that a
client cannot `insert`/`update`/`delete` them.

(Optional) schedule the 30-day / 48-hour purge if pg_cron is enabled:

```sql
select cron.schedule('purge-crash-alerts', '17 * * * *',
  $$select public.purge_crash_alert_data()$$);
```

### 3. Enable anonymous sign-ins

The app authenticates with Supabase **anonymous auth**. Enable it:

- Dashboard → Authentication → Providers → **Anonymous** → enable, **or** in `supabase/config.toml`
  set `[auth] enable_anonymous_sign_ins = true` and push the config.

### 4. Set the secrets

Copy the example, fill in real values locally (the file is gitignored), then push the names/values
to the project. **Never commit the filled-in file.**

```sh
cp supabase/functions/.env.example supabase/functions/.env   # fill in real values; gitignored
# Push them to the project (values are stored encrypted by Supabase, not in Git):
supabase secrets set \
  TWILIO_ACCOUNT_SID=ACxxxxxxxx \
  TWILIO_AUTH_TOKEN=xxxxxxxx \
  TWILIO_FROM_NUMBER=+1XXXXXXXXXX \
  RECIPIENT_HASH_PEPPER="$(openssl rand -hex 32)" \
  CALLBACK_BASE_URL=https://<project-ref>.functions.supabase.co
# Or push the whole file at once:
supabase secrets set --env-file supabase/functions/.env
```

Notes:
- Provide **one** sender: `TWILIO_FROM_NUMBER` **or** `TWILIO_MESSAGING_SERVICE_SID`.
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically in
  deployed functions; set them in `.env` only for local `supabase functions serve`.
- Rotating `RECIPIENT_HASH_PEPPER` invalidates the rate-limit counters (acceptable; contract §14).

### 5. Deploy the functions

```sh
supabase functions deploy send-crash-alert
supabase functions deploy crash-alert-status
# The callback is called by Twilio, not the app, so it must NOT require a Supabase JWT:
supabase functions deploy sms-status-callback --no-verify-jwt
```

`send-crash-alert` and `crash-alert-status` keep JWT verification on (the app sends a Bearer token).
`sms-status-callback` is protected by the Twilio request signature instead, so deploy it with
`--no-verify-jwt`.

### 6. Point Twilio at the callback

`send-crash-alert` sets `StatusCallback` to `CALLBACK_BASE_URL + /sms-status-callback` on every
message, so delivery updates flow automatically once `CALLBACK_BASE_URL` is correct. No extra Twilio
webhook config is needed for status callbacks.

### 7. Kill switch rehearsal (contract §11, C10)

Rehearse before the demo:

- Config flag: `update crash_alert_config set enabled = false where id = 1;` → `send-crash-alert`
  returns `503 service_disabled` and the app falls back to the native composer. Re-enable with `true`.
- Or the environment flag: `supabase secrets set CRASH_ALERTS_DISABLED=1` (and redeploy / unset to
  recover). `crash-alert-status` keeps working either way.

Tunable limits (contract §10) live in the `crash_alert_config` row, so caps can change without a
redeploy.

## Run the tests

```sh
deno test supabase/functions/tests/
```

The tests cover the golden messages **G1–G9** and the **A.3** sub-rule cases (byte-exact bodies and
segment counts), the §5.3 validation matrix, NANP E.164 checks, the Twilio status/error-code maps,
the monotonic/sticky status rule, the `X-Twilio-Signature` algorithm (locked to Twilio's documented
example vector), and the keyed recipient hash.

**Deno was not installed in the build environment where these were written, so `deno test` was not
run here.** Instead, every pure module was transpiled with esbuild and exercised with Node against
the same assertions: message **30/30** (all golden bodies and counts exact), validation **22/22**,
Twilio **18/18** (including the signature vector match and an HMAC cross-check against Node's
`crypto`), hash **4/4**. The pure modules also type-check clean under `tsc --strict`. Run
`deno test` on a machine with Deno to confirm in the real runtime.

## Cost

Cost ≈ segments × recipients × Twilio's per-segment price. Crash alerts render to ~3–4 segments.
See Twilio's pricing page for current per-message prices; this backend does not quote prices. The
per-user / per-recipient / global caps and the spend cap bound the worst case.
