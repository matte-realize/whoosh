# Crash-alert Edge Functions

The backend for the crash-response feature: it texts a rider's emergency contacts on their
behalf. The behavior is defined in `.kiro/team/crash-alert-contract.md`; this folder implements
it. Database tables, row-level security and SQL functions are in
`supabase/migrations/20261024150000_crash_alerts.sql`.

| Function | Who calls it | Contract |
| -------- | ------------ | -------- |
| `send-crash-alert` | the app (signed-in anonymous user) | section 5 |
| `crash-alert-status` | the app | section 6 |
| `sms-status-callback` | Twilio (no JWT; Twilio signature checked first) | section 7 |
| `delete-crash-audit` | the app | section 8 |

## Layout

- `_shared/template.ts` renders the message templates (Appendix A) and counts SMS segments.
- `_shared/validate.ts` validates requests (section 5.3).
- `_shared/provider.ts` holds Twilio sending, signature checks, status and error-code mapping, and the
  keyed recipient hash.
- `_shared/handlers.ts` holds all request logic: kill switch, idempotency, rate limits, the
  unknown-outcome retry rule, status callbacks and deletes. It doesn't depend on Supabase or Twilio.
- `_shared/supabase-store.ts` and `_shared/runtime.ts` are the Deno side: the service-role database
  store, caller authentication and secrets.
- Each function's `index.ts` is about ten lines of wiring.

## Checks (no network, no Docker)

```sh
node supabase/functions/_shared/check.ts            # 106 checks: all 9 golden templates, validation, signatures
node supabase/functions/_shared/handlers-check.ts   # 32 checks: request flows against an in-memory database
supabase test db                                    # includes crash_alerts.test.sql (85 assertions)
```

The Node checks need Node 23.6 or later. They also run under Deno.

## Run locally

Enable anonymous sign-ins by setting `enable_anonymous_sign_ins = true` under `[auth]` in
`supabase/config.toml` before starting the local stack.

```sh
cp supabase/functions/.env.example supabase/functions/.env   # gitignored; fill in Twilio test values
supabase start
supabase functions serve --env-file supabase/functions/.env
```

## Deploy (Role C, hosted project)

Enable anonymous sign-ins in the hosted project's Authentication settings. Before deployment,
re-check isolation with two real anonymous sessions.

1. Apply the migrations: `supabase db push`.
2. Set secrets: `supabase secrets set --env-file supabase/functions/.env`. Use real values here,
   and never commit them.
3. Deploy: `supabase functions deploy send-crash-alert crash-alert-status sms-status-callback delete-crash-audit`.
   `supabase/config.toml` turns off JWT checks for `sms-status-callback` only.
4. In Twilio: set a spend cap, turn auto-recharge off, and limit geographic permissions to US and
   Canada. On a trial account, verify the demo recipients' numbers.
5. Schedule the purge if pg_cron is on: `select cron.schedule('crash-alert-purge', '17 3 * * *', $$select public.crash_alert_purge()$$);`
6. Rehearse the kill switch: `update public.crash_alert_config set enabled = false;` makes sends
   return `503 service_disabled`.

## Known gaps

- **Unverified Twilio details:** the items marked **Verify** in the contract follow Twilio's
  documented behavior as I understand it. They are the signature algorithm, the status names, the
  error codes and `ValidityPeriod`. Check them against Twilio's current documentation before launch.
- **Never run:** the Deno files have never been run. They type-check against the installed
  `supabase-js` types. The logic they call is covered by the Node checks.
- **Idempotency check:** a retried event is compared on `kind`, `templateVersion` and `detectedAt`.
  The rider label isn't stored (data minimization), so a retry with a different label isn't
  detected as a conflict.
- **Production:** sender registration (10DLC or toll-free), App Attest, and a provider data
  agreement (contract section 14).

