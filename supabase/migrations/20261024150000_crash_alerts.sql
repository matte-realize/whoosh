-- Crash alerts: audit, rate-limit, and config tables for the crash-alert SMS backend, plus the
-- three SQL functions the Edge Functions call through RPC.
-- Source of truth: .kiro/team/crash-alert-contract.md (draft 0.1), sections 5.6, 9, 10 and 11.
-- New migration; earlier ones are applied and are not edited.
--
-- WHO WRITES WHAT
--   Clients (the iOS app, the website) never insert, update, or delete these tables. All writes
--   happen inside the Edge Functions (send-crash-alert, sms-status-callback, delete-crash-audit)
--   using the service role, which bypasses RLS. A signed-in client (role `authenticated`, which
--   includes anonymous sign-in users) may only SELECT its own rows in crash_alert_events and
--   crash_alert_deliveries. Nobody but the service role can touch crash_alert_counters or
--   crash_alert_config. `anon` gets nothing.
--
-- WHAT IS NOT STORED
--   No plaintext phone numbers, no message bodies, and no coordinates. A recipient is stored as
--   a keyed hash (HMAC-SHA-256 with a server-side pepper, lowercase hex) plus its last two
--   digits for audit display. An event stores only the location *status*, never a position.
--   Treat recipient_hash as personal data: the phone-number space is small if the pepper leaks.
--
-- RETENTION
--   Events and deliveries: config.audit_retention_days (30). Counters:
--   config.counter_retention_hours (48). public.crash_alert_purge() deletes expired rows; see the
--   note on scheduling at the end of this file.
--
-- GRANTS
--   Supabase no longer grants Data API access to new tables in `public` automatically, and older
--   projects may still carry broad default privileges. Every table and function below therefore
--   starts from "revoke all" and then grants exactly what the contract allows.

-- ---------------------------------------------------------------------------
-- 1. crash_alert_events: one row per (user, crash event, kind)
-- ---------------------------------------------------------------------------

create table public.crash_alert_events (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  -- Client-generated idempotency key. Retries of one event reuse it.
  crash_event_id   uuid not null,
  kind             text not null,
  template_version integer not null,
  consent_version  integer not null,
  detected_at      timestamptz not null,
  delayed_seconds  integer not null default 0,
  -- Status only. 'none' is used for kinds that carry no location (test, intro, all_clear).
  location_status  text not null,
  app_version      text,
  created_at       timestamptz not null default now(),

  constraint crash_alert_events_kind_check
    check (kind in ('crash_alert', 'drill', 'test', 'intro', 'all_clear')),
  constraint crash_alert_events_location_status_check
    check (location_status in ('current', 'last_known', 'unavailable', 'none')),
  constraint crash_alert_events_versions_positive
    check (template_version >= 1 and consent_version >= 1),
  -- Same range as the request validation in contract 5.3.
  constraint crash_alert_events_delayed_seconds_range
    check (delayed_seconds between 0 and 86400),
  -- Idempotency key (contract 5.4 step 5).
  constraint crash_alert_events_user_event_kind_key
    unique (user_id, crash_event_id, kind)
);

-- A user's events, newest first (status lookups, delete-crash-audit). The unique key above also
-- starts with user_id, but not with created_at.
create index crash_alert_events_user_id_created_at_idx
  on public.crash_alert_events (user_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. crash_alert_deliveries: one row per (event, recipient)
-- ---------------------------------------------------------------------------

create table public.crash_alert_deliveries (
  id                   uuid primary key default gen_random_uuid(),
  event_id             uuid not null references public.crash_alert_events (id) on delete cascade,
  user_id              uuid not null references auth.users (id) on delete cascade,
  -- Client-generated contact UUID (not PII).
  recipient_ref        uuid not null,
  -- Keyed hash of the E.164 number, 64 lowercase hex characters (HMAC-SHA-256).
  recipient_hash       text not null,
  -- Last two digits of the number, for audit display.
  recipient_last2      text not null,
  provider             text not null,
  -- Null until the provider accepted the message (and for rows rejected before the provider).
  provider_message_sid text,
  status               text not null default 'queued',
  whoosh_error_code    text,
  provider_error_code  integer,
  segments             integer not null default 0,
  attempt_count        integer not null default 0,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  terminal_at          timestamptz,

  constraint crash_alert_deliveries_status_check
    check (status in ('queued', 'sent', 'delivered', 'undelivered', 'failed', 'rejected')),
  constraint crash_alert_deliveries_recipient_hash_format
    check (recipient_hash ~ '^[0-9a-f]{64}$'),
  constraint crash_alert_deliveries_recipient_last2_format
    check (char_length(recipient_last2) = 2 and recipient_last2 ~ '^[0-9]{2}$'),
  constraint crash_alert_deliveries_segments_nonnegative
    check (segments >= 0),
  constraint crash_alert_deliveries_attempt_count_nonnegative
    check (attempt_count >= 0),
  -- At most one message per recipient per event (contract 5.4 step 7). This index also serves
  -- lookups by event_id and the cascade delete from crash_alert_events.
  constraint crash_alert_deliveries_event_recipient_key
    unique (event_id, recipient_hash)
);

-- The RLS filter on client reads, and the auth.users foreign key.
create index crash_alert_deliveries_user_id_idx
  on public.crash_alert_deliveries (user_id);

-- Status callbacks look deliveries up by provider sid. Unique when present.
create unique index crash_alert_deliveries_provider_message_sid_key
  on public.crash_alert_deliveries (provider_message_sid)
  where provider_message_sid is not null;

-- ---------------------------------------------------------------------------
-- 3. crash_alert_counters: rolling-window rate limiting (contract section 10)
-- ---------------------------------------------------------------------------
--
-- One row per unit consumed. Written only by public.crash_alert_take(). No PII beyond the keyed
-- hash. Purged after config.counter_retention_hours.

create table public.crash_alert_counters (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  bucket         text not null,
  -- Set for recipient-scoped buckets, null otherwise.
  recipient_hash text,
  created_at     timestamptz not null default now(),

  constraint crash_alert_counters_bucket_check
    check (bucket in ('real_alert', 'test_message', 'new_recipient', 'recipient_real',
                      'recipient_test', 'burst', 'global_message')),
  constraint crash_alert_counters_recipient_hash_format
    check (recipient_hash is null or recipient_hash ~ '^[0-9a-f]{64}$')
);

-- Per-user windows (real_alert, test_message, new_recipient, burst, per-user recipient_test).
create index crash_alert_counters_user_bucket_created_at_idx
  on public.crash_alert_counters (user_id, bucket, created_at);

-- Per-recipient windows, including the across-all-users caps.
create index crash_alert_counters_recipient_bucket_created_at_idx
  on public.crash_alert_counters (recipient_hash, bucket, created_at);

-- ---------------------------------------------------------------------------
-- 4. crash_alert_config: single row; kill switch, versions, and limits
-- ---------------------------------------------------------------------------
--
-- Service role only. Limits can be tuned with an UPDATE, without a deploy. Defaults are the
-- contract's section 10 values. The `id` column can only be true, so the table holds one row.

create table public.crash_alert_config (
  id                               boolean primary key default true check (id),
  -- Kill switch (contract 11): false => send-crash-alert returns 503 service_disabled.
  enabled                          boolean not null default true,
  -- Documents that the provider account is a trial (verified recipients only).
  trial_mode                       boolean not null default true,
  min_schema_version               integer not null default 1,
  min_consent_version              integer not null default 1,
  supported_template_versions      integer[] not null default '{1}',
  max_recipients_per_request       integer not null default 3,
  real_alerts_per_user_24h         integer not null default 5,
  test_messages_per_user_24h       integer not null default 10,
  test_messages_per_recipient_24h  integer not null default 3,
  new_recipients_per_user_24h      integer not null default 5,
  real_per_recipient_all_users_24h integer not null default 5,
  test_per_recipient_all_users_24h integer not null default 3,
  burst_requests_per_minute        integer not null default 10,
  global_messages_per_hour         integer not null default 200,
  max_segments                     integer not null default 4,
  audit_retention_days             integer not null default 30,
  counter_retention_hours          integer not null default 48,

  constraint crash_alert_config_versions_positive
    check (min_schema_version >= 1 and min_consent_version >= 1),
  -- A limit of 0 blocks that scope entirely; negative values make no sense.
  constraint crash_alert_config_limits_nonnegative
    check (max_recipients_per_request >= 0
       and real_alerts_per_user_24h >= 0
       and test_messages_per_user_24h >= 0
       and test_messages_per_recipient_24h >= 0
       and new_recipients_per_user_24h >= 0
       and real_per_recipient_all_users_24h >= 0
       and test_per_recipient_all_users_24h >= 0
       and burst_requests_per_minute >= 0
       and global_messages_per_hour >= 0
       and max_segments >= 0),
  -- Audit rows must outlive the 1-hour delete guard (contract 8). Counters must outlive the
  -- longest rate-limit window (24 hours), or purging would reset the caps early.
  constraint crash_alert_config_retention_minimums
    check (audit_retention_days >= 1 and counter_retention_hours >= 24)
);

insert into public.crash_alert_config default values;

-- ---------------------------------------------------------------------------
-- 5. Grants and row level security
-- ---------------------------------------------------------------------------
--
-- Start from nothing for the client roles (this also removes any default privileges Supabase
-- added to new objects in `public`), then grant:
--   authenticated: select on events and deliveries only (RLS limits it to own rows);
--   anon:          nothing on any of the four tables;
--   service_role:  everything on all four (it bypasses RLS; the Edge Functions use it).
-- Without the table privilege a client write fails with 42501 "permission denied" before RLS is
-- consulted, so the missing write policies below are a second barrier, not the only one.

revoke all on table
  public.crash_alert_events,
  public.crash_alert_deliveries,
  public.crash_alert_counters,
  public.crash_alert_config
from public, anon, authenticated;

grant select on table
  public.crash_alert_events,
  public.crash_alert_deliveries
to authenticated;

grant all on table
  public.crash_alert_events,
  public.crash_alert_deliveries,
  public.crash_alert_counters,
  public.crash_alert_config
to service_role;

alter table public.crash_alert_events enable row level security;
alter table public.crash_alert_deliveries enable row level security;
alter table public.crash_alert_counters enable row level security;
alter table public.crash_alert_config enable row level security;

-- Own rows only. (select auth.uid()) is evaluated once per statement.
-- No insert/update/delete policies on any table, and no policies at all on counters and config.
create policy "own crash_alert_events: select" on public.crash_alert_events
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "own crash_alert_deliveries: select" on public.crash_alert_deliveries
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 6. Functions (called by the Edge Functions through RPC with the service role)
-- ---------------------------------------------------------------------------
--
-- All three run with the caller's rights (security invoker, the default). Only service_role may
-- execute them; it has all privileges on the tables and bypasses RLS. search_path is empty, so
-- every name inside is schema-qualified.

-- 6a. crash_alert_take: atomically check one rolling-window limit and, if under it, consume one
-- unit. Returns true when the unit was taken, false when the limit is reached (or p_limit <= 0).
--
--   p_user           the caller (stored on the counter row in every case)
--   p_bucket         one of the crash_alert_counters buckets
--   p_recipient_hash null for user-scoped or global buckets; the keyed hash otherwise
--   p_limit          the limit from crash_alert_config
--   p_window_seconds the rolling window (86400 for daily scopes, 60 for burst, 3600 for global)
--   p_across_users   true to count rows from all users (per-recipient-across-users caps and the
--                    global cap); false to count only p_user's rows
--
-- Concurrency: a transaction-level advisory lock on (bucket, recipient hash, user or '*')
-- serializes concurrent takes on the same key, so two requests cannot both see "count < limit"
-- and both insert. The lock is released when the RPC's transaction commits, by which time the
-- inserted row is visible to the next waiter (read committed: each statement takes a new
-- snapshot). A hash collision between two keys only adds serialization, never a wrong count.
-- Callers that check one bucket both per user and across users must use one call per bucket
-- consistently, because every successful call inserts a row.
create function public.crash_alert_take(
  p_user uuid,
  p_bucket text,
  p_recipient_hash text,
  p_limit integer,
  p_window_seconds integer,
  p_across_users boolean default false
)
returns boolean
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_across boolean := coalesce(p_across_users, false);
  v_count  bigint;
begin
  if p_limit is null or p_limit <= 0 then
    return false;
  end if;

  if p_user is null or p_bucket is null then
    raise exception 'crash_alert_take: p_user and p_bucket are required'
      using errcode = '22004';
  end if;

  if p_window_seconds is null or p_window_seconds <= 0 then
    raise exception 'crash_alert_take: p_window_seconds must be positive'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'crash_alert_take|' || p_bucket
        || '|' || coalesce(p_recipient_hash, '')
        || '|' || case when v_across then '*' else p_user::text end,
      0
    )
  );

  select count(*)
    into v_count
  from public.crash_alert_counters c
  where c.bucket = p_bucket
    and c.created_at > pg_catalog.now() - pg_catalog.make_interval(secs => p_window_seconds)
    and (p_recipient_hash is null or c.recipient_hash = p_recipient_hash)
    and (v_across or c.user_id = p_user);

  if v_count >= p_limit then
    return false;
  end if;

  insert into public.crash_alert_counters (user_id, bucket, recipient_hash)
  values (p_user, p_bucket, p_recipient_hash);

  return true;
end;
$$;

revoke all on function public.crash_alert_take(uuid, text, text, integer, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.crash_alert_take(uuid, text, text, integer, integer, boolean)
  to service_role;

-- 6b. crash_alert_apply_status: apply a provider status to a delivery, following contract 5.6.
--   Rank: queued = 1, sent = 2, delivered / undelivered / failed / rejected = 3 (terminal).
--   Statuses never regress, and a terminal status is sticky (a later terminal status is ignored).
-- Returns:
--   'invalid_status' p_status is not one of the six statuses (checked first, before any lock)
--   'unknown_sid'    no delivery has this provider_message_sid
--   'applied'        the status moved forward; error codes are kept unless new ones are given
--   'ignored'        duplicate, out-of-order, or after a terminal status; nothing changed
-- The row is locked (select ... for update) so concurrent callbacks for one sid apply in turn.
create function public.crash_alert_apply_status(
  p_sid text,
  p_status text,
  p_provider_error_code integer default null,
  p_whoosh_error_code text default null
)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_id           uuid;
  v_current      text;
  v_current_rank integer;
  v_new_rank     integer;
begin
  v_new_rank := case p_status
    when 'queued'      then 1
    when 'sent'        then 2
    when 'delivered'   then 3
    when 'undelivered' then 3
    when 'failed'      then 3
    when 'rejected'    then 3
    else null
  end;

  if v_new_rank is null then
    return 'invalid_status';
  end if;

  if p_sid is null then
    return 'unknown_sid';
  end if;

  select d.id, d.status
    into v_id, v_current
  from public.crash_alert_deliveries d
  where d.provider_message_sid = p_sid
  for update;

  if not found then
    return 'unknown_sid';
  end if;

  v_current_rank := case v_current
    when 'queued' then 1
    when 'sent'   then 2
    else 3
  end;

  -- Terminal is sticky.
  if v_current_rank = 3 then
    return 'ignored';
  end if;

  -- Never regress; a repeat of the current status is a no-op.
  if v_new_rank <= v_current_rank then
    return 'ignored';
  end if;

  update public.crash_alert_deliveries d
     set status              = p_status,
         provider_error_code = coalesce(p_provider_error_code, d.provider_error_code),
         whoosh_error_code   = coalesce(p_whoosh_error_code, d.whoosh_error_code),
         updated_at          = pg_catalog.now(),
         terminal_at         = case when v_new_rank = 3 then pg_catalog.now() else d.terminal_at end
   where d.id = v_id;

  return 'applied';
end;
$$;

revoke all on function public.crash_alert_apply_status(text, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.crash_alert_apply_status(text, text, integer, text)
  to service_role;

-- 6c. crash_alert_purge: delete expired audit and counter rows. Returns the number of rows
-- deleted (events + counters; deliveries go with their events by cascade and are not counted).
--
-- SCHEDULING: a scheduled job should call this once a day. If pg_cron is enabled on the project,
-- for example:
--   select cron.schedule('crash-alert-purge', '17 3 * * *', $cron$select public.crash_alert_purge()$cron$);
-- Enabling pg_cron and creating that job is Role C's step on the hosted project. This migration
-- deliberately does not create the job (pg_cron may not be enabled, and the local stack does not
-- need it). A job run by the table owner (postgres) can execute this function.
create function public.crash_alert_purge()
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_audit_days    integer;
  v_counter_hours integer;
  v_events        integer;
  v_counters      integer;
begin
  select c.audit_retention_days, c.counter_retention_hours
    into v_audit_days, v_counter_hours
  from public.crash_alert_config c
  where c.id;

  if not found then
    raise exception 'crash_alert_purge: crash_alert_config row is missing';
  end if;

  delete from public.crash_alert_events e
  where e.created_at < pg_catalog.now() - pg_catalog.make_interval(days => v_audit_days);
  get diagnostics v_events = row_count;

  delete from public.crash_alert_counters c
  where c.created_at < pg_catalog.now() - pg_catalog.make_interval(hours => v_counter_hours);
  get diagnostics v_counters = row_count;

  return v_events + v_counters;
end;
$$;

revoke all on function public.crash_alert_purge()
  from public, anon, authenticated;
grant execute on function public.crash_alert_purge()
  to service_role;

