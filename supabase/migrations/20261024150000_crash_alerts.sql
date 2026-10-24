-- crash_alert_*: audit, delivery, rate-limit, and config tables for the opt-in crash-alert SMS
-- backend. Source of truth: .kiro/team/crash-alert-contract.md (DRAFT 0.1, drafted by the iOS
-- owner for Role C to review; see supabase/functions/README.md).
--
-- Privacy invariants (contract §4, §9, privacy.md "Emergency contacts and crash alerts"):
--   * No table stores plaintext phone numbers, message bodies, or coordinates.
--     Deliveries hold only a keyed HMAC of the E.164 number and its last two digits.
--   * location_status is a status word only ('current' | 'last_known' | 'unavailable' | 'none').
--   * Clients never insert/update/delete these tables. All writes happen inside the Edge
--     Functions with the service role (which bypasses RLS). Clients may only SELECT their own
--     rows in events and deliveries; counters and config are not client-readable at all.
--   * Audit retention is 30 days; counters 48 hours (see the purge function at the end).
--
-- Anonymous sign-in users have the "authenticated" role, so the policies below apply to them.
-- Timestamps are timestamptz (UTC). UUIDs are lowercase canonical.

-- ---------------------------------------------------------------------------
-- 1. crash_alert_events: one row per (user, crashEventId, kind). Idempotency anchor.
-- ---------------------------------------------------------------------------

create table crash_alert_events (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  crash_event_id    uuid not null,
  kind              text not null check (kind in ('crash_alert', 'drill', 'test', 'intro', 'all_clear')),
  template_version  int  not null,
  consent_version   int  not null,
  detected_at       timestamptz not null,
  delayed_seconds   int  not null default 0 check (delayed_seconds between 0 and 86400),
  -- Status only, never coordinates.
  location_status   text not null default 'none'
                      check (location_status in ('current', 'last_known', 'unavailable', 'none')),
  app_version       text check (app_version is null or char_length(app_version) <= 32),
  created_at        timestamptz not null default now(),

  -- Idempotency: a repeated request with the same (user, crashEventId, kind) maps to this row.
  constraint crash_alert_events_idem unique (user_id, crash_event_id, kind)
);

-- ---------------------------------------------------------------------------
-- 2. crash_alert_deliveries: one row per (event, recipient hash). Send-once anchor.
-- ---------------------------------------------------------------------------

create table crash_alert_deliveries (
  id                   uuid primary key default gen_random_uuid(),
  event_id             uuid not null references crash_alert_events (id) on delete cascade,
  user_id              uuid not null,
  recipient_ref        uuid not null,
  -- Keyed HMAC-SHA-256 (server pepper secret) of the E.164 number, hex. A keyed hash (not a
  -- per-row salt) lets cross-row rate limiting work; treated as personal data (see contract §9).
  recipient_hash       text not null,
  recipient_last2      text not null check (char_length(recipient_last2) = 2),
  provider             text not null default 'twilio',
  provider_message_sid text unique,
  status               text not null default 'queued'
                         check (status in ('queued', 'sent', 'delivered',
                                           'undelivered', 'failed', 'rejected')),
  whoosh_error_code    text,
  provider_error_code  int,
  segments             int not null default 0 check (segments >= 0),
  attempt_count        int not null default 0 check (attempt_count >= 0),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  terminal_at          timestamptz,

  -- Send-once per recipient per event.
  constraint crash_alert_deliveries_once unique (event_id, recipient_hash)
);

-- ---------------------------------------------------------------------------
-- 3. crash_alert_counters: rolling-window rate-limit events. No PII beyond the keyed hash.
-- ---------------------------------------------------------------------------

create table crash_alert_counters (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid,
  bucket         text not null check (bucket in ('real_alert', 'test_message', 'new_recipient',
                                                 'recipient_real', 'recipient_test', 'burst',
                                                 'global')),
  recipient_hash text,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. crash_alert_config: single tunable config row. Service role only; no client access.
-- ---------------------------------------------------------------------------

create table crash_alert_config (
  id                          int primary key default 1 check (id = 1),
  enabled                     boolean not null default true,     -- kill switch
  trial_mode                  boolean not null default true,     -- provider trial account
  min_schema_version          int not null default 1,
  min_consent_version         int not null default 1,
  supported_template_versions int[] not null default '{1}',
  -- Limits from contract §10 (tunable without a redeploy).
  recipients_per_request      int not null default 3,
  real_alerts_per_user_24h    int not null default 5,
  test_messages_per_user_24h  int not null default 10,
  test_per_recipient_user_24h int not null default 3,
  new_recipients_per_user_24h int not null default 5,
  real_per_recipient_all_24h  int not null default 5,
  test_per_recipient_all_24h  int not null default 3,
  burst_per_user_per_min      int not null default 10,
  global_per_hour             int not null default 200,
  max_segments                int not null default 4,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

insert into crash_alert_config (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Data API grants.
-- Supabase no longer grants access to new public tables automatically, so grant explicitly
-- (see the note in 20261024120000_rides.sql). Clients get SELECT only on events and deliveries;
-- RLS below restricts to own rows. No grant to anon anywhere. No client grant on counters/config.
-- service_role is used inside the Edge Functions and bypasses RLS for the function writes.
-- ---------------------------------------------------------------------------

grant select on public.crash_alert_events to authenticated;
grant select on public.crash_alert_deliveries to authenticated;

grant select, insert, update, delete on public.crash_alert_events to service_role;
grant select, insert, update, delete on public.crash_alert_deliveries to service_role;
grant select, insert, update, delete on public.crash_alert_counters to service_role;
grant select, insert, update, delete on public.crash_alert_config to service_role;

-- ---------------------------------------------------------------------------
-- 6. Row level security.
-- (select auth.uid()) is evaluated once per statement instead of per row.
-- No write policies for the authenticated role: with only SELECT granted and only SELECT
-- policies present, inserts/updates/deletes by a client are refused. Counters and config have
-- RLS enabled with no policies and no client grant, so clients cannot touch them at all.
-- ---------------------------------------------------------------------------

alter table crash_alert_events enable row level security;
create policy "own crash events: select" on crash_alert_events
  for select to authenticated
  using (user_id = (select auth.uid()));

alter table crash_alert_deliveries enable row level security;
create policy "own crash deliveries: select" on crash_alert_deliveries
  for select to authenticated
  using (user_id = (select auth.uid()));

alter table crash_alert_counters enable row level security;  -- no policies: clients see nothing
alter table crash_alert_config   enable row level security;  -- no policies: clients see nothing

-- ---------------------------------------------------------------------------
-- 7. Indexes.
-- ---------------------------------------------------------------------------

-- Status reads and cascade delete from events.
create index crash_alert_deliveries_event_idx on crash_alert_deliveries (event_id);
-- Per-user status reads (crash-alert-status).
create index crash_alert_events_user_crash_idx on crash_alert_events (user_id, crash_event_id);
-- Rolling-window counting: by user+bucket and by recipient+bucket (cross-user recipient cap).
create index crash_alert_counters_user_bucket_idx
  on crash_alert_counters (user_id, bucket, created_at);
create index crash_alert_counters_recipient_bucket_idx
  on crash_alert_counters (recipient_hash, bucket, created_at);

-- ---------------------------------------------------------------------------
-- 8. Retention purge. Call from a scheduled job (pg_cron) or a manual admin run.
-- Audit rows (events + their deliveries via cascade) older than 30 days; counters older than
-- 48 hours. SECURITY DEFINER so the scheduler can run it; execute granted to service_role only.
-- ---------------------------------------------------------------------------

create function public.purge_crash_alert_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.crash_alert_events  where created_at < now() - interval '30 days';
  delete from public.crash_alert_counters where created_at < now() - interval '48 hours';
end;
$$;

revoke all on function public.purge_crash_alert_data() from public, anon, authenticated;
grant execute on function public.purge_crash_alert_data() to service_role;

-- To schedule (run once, by Role C, if pg_cron is enabled on the project):
--   select cron.schedule('purge-crash-alerts', '17 * * * *', $$select public.purge_crash_alert_data()$$);
