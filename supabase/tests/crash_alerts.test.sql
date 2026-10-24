-- Tests for migration 20261024150000_crash_alerts.sql: the crash-alert tables (constraints,
-- grants, RLS) and the functions crash_alert_take, crash_alert_apply_status, crash_alert_purge.
-- Spec: .kiro/team/crash-alert-contract.md, sections 5.6, 9, 10 and 11.
--
-- HOW TO RUN: supabase test db   (runs every file in supabase/tests/)
-- The file runs in one transaction and rolls back, so it leaves no data behind.
--
-- SESSIONS are simulated as in rls_rides.test.sql:
--   reset role;
--   select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--   set local role authenticated;
--
-- TIME: now() is fixed for the whole transaction, so "old" rows get an explicit created_at in
-- the past, and rows inserted by the functions get created_at = now().
--
-- FIXTURE IDS all start with 'ca000000-' so they cannot clash with other test files.
--   users:      A = ...00000000000a, B = ...00000000000b
--   events:     101 A crash_alert (now)      102 A test (now)
--               103 B crash_alert (now)      104 A crash_alert (31 days old, purged)
--               105 A all_clear (now; inserted by assertion 23, same crash_event_id as 101)
--               106 B drill (29 days old, kept by the purge)
--   deliveries: 301 A on 101 (queued)        302 A on 101 (queued)
--               303 B on 103 (sent)          304 A on 104 (delivered, 31 days old)
--               305, 306 A on 102 (rejected, no sid; inserted by assertion 26)
--   counters:   501 A test_message (3 days old, outside every window, purged)
--               502 A burst (1 hour old, kept)

begin;

select plan(85);

-- Start from a known state: no crash-alert rows (deliveries go by cascade). The config row is
-- replaced further down, after assertion 9 has checked the one the migration inserted.
delete from public.crash_alert_events;
delete from public.crash_alert_counters;

-- ---------------------------------------------------------------------------
-- Fixtures (superuser)
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email)
values
  ('ca000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'crash-alert-a@example.test'),
  ('ca000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'crash-alert-b@example.test');

insert into public.crash_alert_events
  (id, user_id, crash_event_id, kind, template_version, consent_version, detected_at,
   delayed_seconds, location_status, app_version, created_at)
values
  ('ca000000-0000-4000-8000-000000000101', 'ca000000-0000-4000-8000-00000000000a',
   'ca000000-0000-4000-8000-000000000201', 'crash_alert', 1, 1, now() - interval '5 minutes',
   0, 'current', '1.0 (42)', now()),
  ('ca000000-0000-4000-8000-000000000102', 'ca000000-0000-4000-8000-00000000000a',
   'ca000000-0000-4000-8000-000000000202', 'test', 1, 1, now() - interval '10 minutes',
   0, 'none', '1.0 (42)', now()),
  ('ca000000-0000-4000-8000-000000000103', 'ca000000-0000-4000-8000-00000000000b',
   'ca000000-0000-4000-8000-000000000203', 'crash_alert', 1, 1, now() - interval '5 minutes',
   0, 'unavailable', '1.0 (42)', now()),
  ('ca000000-0000-4000-8000-000000000104', 'ca000000-0000-4000-8000-00000000000a',
   'ca000000-0000-4000-8000-000000000204', 'crash_alert', 1, 1, now() - interval '31 days',
   0, 'last_known', '1.0 (41)', now() - interval '31 days'),
  ('ca000000-0000-4000-8000-000000000106', 'ca000000-0000-4000-8000-00000000000b',
   'ca000000-0000-4000-8000-000000000206', 'drill', 1, 1, now() - interval '29 days',
   0, 'current', '1.0 (41)', now() - interval '29 days');

insert into public.crash_alert_deliveries
  (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider,
   provider_message_sid, status, segments, attempt_count, created_at, updated_at, terminal_at)
values
  ('ca000000-0000-4000-8000-000000000301', 'ca000000-0000-4000-8000-000000000101',
   'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000401',
   repeat('a', 64), '23', 'twilio', 'SMca_test_301', 'queued', 4, 1, now(), now(), null),
  ('ca000000-0000-4000-8000-000000000302', 'ca000000-0000-4000-8000-000000000101',
   'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000402',
   repeat('b', 64), '24', 'twilio', 'SMca_test_302', 'queued', 4, 1, now(), now(), null),
  ('ca000000-0000-4000-8000-000000000303', 'ca000000-0000-4000-8000-000000000103',
   'ca000000-0000-4000-8000-00000000000b', 'ca000000-0000-4000-8000-000000000403',
   repeat('a', 64), '23', 'twilio', 'SMca_test_303', 'sent', 3, 1, now(), now(), null),
  ('ca000000-0000-4000-8000-000000000304', 'ca000000-0000-4000-8000-000000000104',
   'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000404',
   repeat('c', 64), '25', 'twilio', 'SMca_test_304', 'delivered', 4, 1,
   now() - interval '31 days', now() - interval '31 days', now() - interval '31 days');

insert into public.crash_alert_counters (id, user_id, bucket, recipient_hash, created_at)
values
  ('ca000000-0000-4000-8000-000000000501', 'ca000000-0000-4000-8000-00000000000a',
   'test_message', null, now() - interval '3 days'),
  ('ca000000-0000-4000-8000-000000000502', 'ca000000-0000-4000-8000-00000000000a',
   'burst', null, now() - interval '1 hour');

-- ---------------------------------------------------------------------------
-- Catalog: tables exist, RLS is on (superuser)
-- ---------------------------------------------------------------------------

-- 1
select has_table('public', 'crash_alert_events', 'table crash_alert_events exists');
-- 2
select has_table('public', 'crash_alert_deliveries', 'table crash_alert_deliveries exists');
-- 3
select has_table('public', 'crash_alert_counters', 'table crash_alert_counters exists');
-- 4
select has_table('public', 'crash_alert_config', 'table crash_alert_config exists');

-- 5
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.crash_alert_events'::regclass),
  'RLS is enabled on crash_alert_events'
);
-- 6
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.crash_alert_deliveries'::regclass),
  'RLS is enabled on crash_alert_deliveries'
);
-- 7
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.crash_alert_counters'::regclass),
  'RLS is enabled on crash_alert_counters'
);
-- 8
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.crash_alert_config'::regclass),
  'RLS is enabled on crash_alert_config'
);

-- ---------------------------------------------------------------------------
-- Config: single row, contract defaults (superuser)
-- ---------------------------------------------------------------------------

-- 9 (the row the migration inserted)
select is(
  (select count(*) from public.crash_alert_config),
  1::bigint,
  'crash_alert_config has exactly one row after the migration'
);

-- Replace it with a fresh default row, so assertion 10 checks the column defaults and the purge
-- assertions do not depend on any local tuning. The rollback restores the original row.
delete from public.crash_alert_config;
insert into public.crash_alert_config default values;

-- 10
select ok(
  (select enabled
      and trial_mode
      and min_schema_version = 1
      and min_consent_version = 1
      and supported_template_versions = '{1}'::integer[]
      and max_recipients_per_request = 3
      and real_alerts_per_user_24h = 5
      and test_messages_per_user_24h = 10
      and test_messages_per_recipient_24h = 3
      and new_recipients_per_user_24h = 5
      and real_per_recipient_all_users_24h = 5
      and test_per_recipient_all_users_24h = 3
      and burst_requests_per_minute = 10
      and global_messages_per_hour = 200
      and max_segments = 4
      and audit_retention_days = 30
      and counter_retention_hours = 48
   from public.crash_alert_config),
  'crash_alert_config defaults match contract sections 10 and 11'
);

-- 11
select throws_ok(
  $$insert into public.crash_alert_config default values$$,
  '23505',
  null,
  'a second config row is rejected (duplicate primary key)'
);

-- 12
select throws_ok(
  $$insert into public.crash_alert_config (id) values (false)$$,
  '23514',
  null,
  'a config row with id = false is rejected (check id)'
);

-- ---------------------------------------------------------------------------
-- Constraints (superuser)
-- ---------------------------------------------------------------------------

-- 13
select throws_ok(
  $$insert into public.crash_alert_events
      (id, user_id, crash_event_id, kind, template_version, consent_version, detected_at,
       delayed_seconds, location_status)
    values
      ('ca000000-0000-4000-8000-0000000001f1', 'ca000000-0000-4000-8000-00000000000a',
       'ca000000-0000-4000-8000-0000000002f1', 'panic', 1, 1, now(), 0, 'current')$$,
  '23514',
  null,
  'an event with an unknown kind is rejected'
);

-- 14
select throws_ok(
  $$insert into public.crash_alert_events
      (id, user_id, crash_event_id, kind, template_version, consent_version, detected_at,
       delayed_seconds, location_status)
    values
      ('ca000000-0000-4000-8000-0000000001f2', 'ca000000-0000-4000-8000-00000000000a',
       'ca000000-0000-4000-8000-0000000002f2', 'crash_alert', 1, 1, now(), 0, 'somewhere')$$,
  '23514',
  null,
  'an event with an unknown location_status is rejected'
);

-- 15
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider, status)
    values
      ('ca000000-0000-4000-8000-0000000003f1', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f1',
       repeat('d', 64), '11', 'twilio', 'read')$$,
  '23514',
  null,
  'a delivery with an unknown status is rejected'
);

-- 16
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-0000000003f2', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f2',
       repeat('d', 63), '11', 'twilio')$$,
  '23514',
  null,
  'a recipient_hash of 63 hex characters is rejected'
);

-- 17
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-0000000003f3', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f3',
       repeat('D', 64), '11', 'twilio')$$,
  '23514',
  null,
  'an uppercase recipient_hash is rejected (lowercase hex only)'
);

-- 18
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-0000000003f4', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f4',
       repeat('d', 64), '1x', 'twilio')$$,
  '23514',
  null,
  'a recipient_last2 with a non-digit is rejected'
);

-- 19
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-0000000003f5', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f5',
       repeat('d', 64), '123', 'twilio')$$,
  '23514',
  null,
  'a recipient_last2 of three digits is rejected'
);

-- 20
select throws_ok(
  $$insert into public.crash_alert_counters (user_id, bucket)
    values ('ca000000-0000-4000-8000-00000000000a', 'weekly')$$,
  '23514',
  null,
  'a counter with an unknown bucket is rejected'
);

-- 21
select throws_ok(
  $$insert into public.crash_alert_counters (user_id, bucket, recipient_hash)
    values ('ca000000-0000-4000-8000-00000000000a', 'recipient_real', 'not-a-hash')$$,
  '23514',
  null,
  'a counter with a malformed recipient_hash is rejected'
);

-- 22 (same user, crash_event_id and kind as event 101)
select throws_ok(
  $$insert into public.crash_alert_events
      (id, user_id, crash_event_id, kind, template_version, consent_version, detected_at,
       delayed_seconds, location_status)
    values
      ('ca000000-0000-4000-8000-0000000001f3', 'ca000000-0000-4000-8000-00000000000a',
       'ca000000-0000-4000-8000-000000000201', 'crash_alert', 1, 1, now(), 0, 'current')$$,
  '23505',
  null,
  'a duplicate (user_id, crash_event_id, kind) is rejected'
);

-- 23 (same crash_event_id as 101 but kind all_clear: allowed, and kept as event 105)
select lives_ok(
  $$insert into public.crash_alert_events
      (id, user_id, crash_event_id, kind, template_version, consent_version, detected_at,
       delayed_seconds, location_status)
    values
      ('ca000000-0000-4000-8000-000000000105', 'ca000000-0000-4000-8000-00000000000a',
       'ca000000-0000-4000-8000-000000000201', 'all_clear', 1, 1, now() - interval '5 minutes',
       0, 'none')$$,
  'the same crash_event_id with a different kind is allowed'
);

-- 24 (event 101 already has a delivery for repeat('a', 64))
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-0000000003f6', 'ca000000-0000-4000-8000-000000000101',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f6',
       repeat('a', 64), '23', 'twilio')$$,
  '23505',
  null,
  'a duplicate (event_id, recipient_hash) is rejected'
);

-- 25 (sid already used by delivery 301)
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider,
       provider_message_sid)
    values
      ('ca000000-0000-4000-8000-0000000003f7', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000004f7',
       repeat('d', 64), '11', 'twilio', 'SMca_test_301')$$,
  '23505',
  null,
  'a duplicate provider_message_sid is rejected'
);

-- 26 (rows rejected before the provider have no sid; several nulls are fine. Kept as 305, 306)
select lives_ok(
  $$insert into public.crash_alert_deliveries
      (id, event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider,
       provider_message_sid, status, whoosh_error_code, terminal_at)
    values
      ('ca000000-0000-4000-8000-000000000305', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000405',
       repeat('e', 64), '26', 'twilio', null, 'rejected', 'rate_limited_recipient', now()),
      ('ca000000-0000-4000-8000-000000000306', 'ca000000-0000-4000-8000-000000000102',
       'ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000406',
       repeat('f', 64), '27', 'twilio', null, 'rejected', 'rate_limited_recipient', now())$$,
  'several deliveries without a provider_message_sid are allowed'
);

-- ---------------------------------------------------------------------------
-- User A (authenticated): own rows only, read-only, no counters/config/functions
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"ca000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

-- 27 (101, 102, 104, 105)
select is(
  (select count(*) from public.crash_alert_events),
  4::bigint,
  'user A sees only their own 4 events'
);

-- 28 (301, 302, 304, 305, 306)
select is(
  (select count(*) from public.crash_alert_deliveries),
  5::bigint,
  'user A sees only their own 5 deliveries'
);

-- 29
select is(
  (select count(*) from public.crash_alert_events
     where user_id = 'ca000000-0000-4000-8000-00000000000b'),
  0::bigint,
  'user A sees 0 of user B''s events'
);

-- 30
select is(
  (select count(*) from public.crash_alert_deliveries
     where user_id = 'ca000000-0000-4000-8000-00000000000b'
        or event_id = 'ca000000-0000-4000-8000-000000000103'),
  0::bigint,
  'user A sees 0 of user B''s deliveries'
);

-- 31
select throws_ok(
  $$insert into public.crash_alert_events
      (user_id, crash_event_id, kind, template_version, consent_version, detected_at,
       delayed_seconds, location_status)
    values
      ('ca000000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-0000000002f4',
       'test', 1, 1, now(), 0, 'none')$$,
  '42501',
  null,
  'authenticated cannot insert crash_alert_events'
);

-- 32
select throws_ok(
  $$update public.crash_alert_events set app_version = 'x'
      where id = 'ca000000-0000-4000-8000-000000000101'$$,
  '42501',
  null,
  'authenticated cannot update crash_alert_events'
);

-- 33
select throws_ok(
  $$delete from public.crash_alert_events
      where id = 'ca000000-0000-4000-8000-000000000101'$$,
  '42501',
  null,
  'authenticated cannot delete crash_alert_events'
);

-- 34
select throws_ok(
  $$insert into public.crash_alert_deliveries
      (event_id, user_id, recipient_ref, recipient_hash, recipient_last2, provider)
    values
      ('ca000000-0000-4000-8000-000000000101', 'ca000000-0000-4000-8000-00000000000a',
       'ca000000-0000-4000-8000-0000000004f8', repeat('9', 64), '99', 'twilio')$$,
  '42501',
  null,
  'authenticated cannot insert crash_alert_deliveries'
);

-- 35
select throws_ok(
  $$update public.crash_alert_deliveries set status = 'delivered'
      where id = 'ca000000-0000-4000-8000-000000000301'$$,
  '42501',
  null,
  'authenticated cannot update crash_alert_deliveries'
);

-- 36
select throws_ok(
  $$delete from public.crash_alert_deliveries
      where id = 'ca000000-0000-4000-8000-000000000301'$$,
  '42501',
  null,
  'authenticated cannot delete crash_alert_deliveries'
);

-- 37
select throws_ok(
  $$select count(*) from public.crash_alert_counters$$,
  '42501',
  null,
  'authenticated cannot select crash_alert_counters'
);

-- 38
select throws_ok(
  $$select count(*) from public.crash_alert_config$$,
  '42501',
  null,
  'authenticated cannot select crash_alert_config'
);

-- 39
select throws_ok(
  $$select public.crash_alert_take(
      'ca000000-0000-4000-8000-00000000000a'::uuid, 'burst', null, 10, 60)$$,
  '42501',
  null,
  'authenticated cannot execute crash_alert_take'
);

-- 40
select throws_ok(
  $$select public.crash_alert_apply_status('SMca_test_301', 'delivered')$$,
  '42501',
  null,
  'authenticated cannot execute crash_alert_apply_status'
);

-- 41
select throws_ok(
  $$select public.crash_alert_purge()$$,
  '42501',
  null,
  'authenticated cannot execute crash_alert_purge'
);

-- ---------------------------------------------------------------------------
-- User B (authenticated): sees their own rows
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"ca000000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;

-- 42 (103, 106)
select is(
  (select count(*) from public.crash_alert_events),
  2::bigint,
  'user B sees only their own 2 events'
);

-- 43 (303)
select is(
  (select count(*) from public.crash_alert_deliveries),
  1::bigint,
  'user B sees only their own 1 delivery'
);

-- ---------------------------------------------------------------------------
-- anon: nothing
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 44
select throws_ok(
  $$select count(*) from public.crash_alert_events$$,
  '42501',
  null,
  'anon cannot select crash_alert_events'
);

-- 45
select throws_ok(
  $$select count(*) from public.crash_alert_deliveries$$,
  '42501',
  null,
  'anon cannot select crash_alert_deliveries'
);

-- 46
select throws_ok(
  $$select count(*) from public.crash_alert_counters$$,
  '42501',
  null,
  'anon cannot select crash_alert_counters'
);

-- 47
select throws_ok(
  $$select count(*) from public.crash_alert_config$$,
  '42501',
  null,
  'anon cannot select crash_alert_config'
);

-- 48
select throws_ok(
  $$select public.crash_alert_take(
      'ca000000-0000-4000-8000-00000000000a'::uuid, 'burst', null, 10, 60)$$,
  '42501',
  null,
  'anon cannot execute crash_alert_take'
);

-- ---------------------------------------------------------------------------
-- crash_alert_take (superuser)
-- ---------------------------------------------------------------------------

reset role;

-- 49, 50, 51: limit 2 per user. Counter 501 (A, test_message, 3 days old) is outside the
-- 86400 s window; if it were counted, 50 would already return false.
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'test_message', null, 2, 86400),
  true,
  'take: user A, limit 2, first call returns true'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'test_message', null, 2, 86400),
  true,
  'take: user A, limit 2, second call returns true (the 3-day-old row is not counted)'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'test_message', null, 2, 86400),
  false,
  'take: user A, limit 2, third call returns false'
);

-- 52 (501 plus the two taken above; the refused call inserted nothing)
select is(
  (select count(*) from public.crash_alert_counters
     where user_id = 'ca000000-0000-4000-8000-00000000000a' and bucket = 'test_message'),
  3::bigint,
  'take: only successful calls insert a counter row'
);

-- 53
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000b'::uuid, 'test_message', null, 2, 86400),
  true,
  'take: user B is counted independently of user A'
);

-- 54 (across users: A's 2 recent rows + B's 1 = 3 >= 2)
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000b'::uuid, 'test_message', null, 2, 86400, true),
  false,
  'take: with p_across_users the rows of all users are counted'
);

-- 55, 56, 57: one recipient hash across all users, limit 2
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'recipient_real', repeat('a', 64), 2, 86400, true),
  true,
  'take: recipient across users, user A, first call returns true'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000b'::uuid, 'recipient_real', repeat('a', 64), 2, 86400, true),
  true,
  'take: recipient across users, user B, second call returns true'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'recipient_real', repeat('a', 64), 2, 86400, true),
  false,
  'take: recipient across users, third call (any user) returns false'
);

-- 58, 59, 60: per user and per recipient, limit 1
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'recipient_test', repeat('a', 64), 1, 86400),
  true,
  'take: per-recipient, recipient a, first call returns true'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'recipient_test', repeat('b', 64), 1, 86400),
  true,
  'take: per-recipient, a different recipient is counted separately'
);
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'recipient_test', repeat('a', 64), 1, 86400),
  false,
  'take: per-recipient, recipient a, second call returns false'
);

-- 61
select is(
  public.crash_alert_take('ca000000-0000-4000-8000-00000000000a'::uuid, 'burst', null, 0, 60),
  false,
  'take: limit 0 returns false'
);

-- 62 (only fixture 502)
select is(
  (select count(*) from public.crash_alert_counters
     where user_id = 'ca000000-0000-4000-8000-00000000000a' and bucket = 'burst'),
  1::bigint,
  'take: limit 0 inserts no counter row'
);

-- ---------------------------------------------------------------------------
-- crash_alert_apply_status (superuser)
-- ---------------------------------------------------------------------------

-- 63
select is(
  public.crash_alert_apply_status('SMca_no_such_sid', 'sent'),
  'unknown_sid'::text,
  'apply_status: unknown sid returns unknown_sid'
);

-- 64
select is(
  public.crash_alert_apply_status('SMca_test_301', 'read'),
  'invalid_status'::text,
  'apply_status: unknown status returns invalid_status'
);

-- 65
select is(
  public.crash_alert_apply_status('SMca_test_301', 'sent'),
  'applied'::text,
  'apply_status: queued -> sent is applied'
);

-- 66
select is(
  public.crash_alert_apply_status('SMca_test_301', 'queued'),
  'ignored'::text,
  'apply_status: sent -> queued is ignored (no regression)'
);

-- 67
select is(
  (select status from public.crash_alert_deliveries
     where id = 'ca000000-0000-4000-8000-000000000301'),
  'sent'::text,
  'apply_status: status is still sent after the late queued callback'
);

-- 68
select is(
  public.crash_alert_apply_status('SMca_test_301', 'sent'),
  'ignored'::text,
  'apply_status: a duplicate sent callback is ignored'
);

-- 69
select is(
  public.crash_alert_apply_status('SMca_test_301', 'delivered'),
  'applied'::text,
  'apply_status: sent -> delivered is applied'
);

-- 70
select ok(
  (select status = 'delivered' and terminal_at is not null
     from public.crash_alert_deliveries
     where id = 'ca000000-0000-4000-8000-000000000301'),
  'apply_status: delivered sets terminal_at'
);

-- 71
select is(
  public.crash_alert_apply_status('SMca_test_301', 'failed', 30003, 'recipient_unreachable'),
  'ignored'::text,
  'apply_status: delivered -> failed is ignored (terminal is sticky)'
);

-- 72
select ok(
  (select status = 'delivered' and provider_error_code is null and whoosh_error_code is null
     from public.crash_alert_deliveries
     where id = 'ca000000-0000-4000-8000-000000000301'),
  'apply_status: the ignored failed callback changed nothing'
);

-- 73 (delivery 302 is queued)
select is(
  public.crash_alert_apply_status('SMca_test_302', 'undelivered', 30006, 'recipient_landline'),
  'applied'::text,
  'apply_status: queued -> undelivered with error codes is applied'
);

-- 74
select ok(
  (select status = 'undelivered'
          and provider_error_code = 30006
          and whoosh_error_code = 'recipient_landline'
          and terminal_at is not null
     from public.crash_alert_deliveries
     where id = 'ca000000-0000-4000-8000-000000000302'),
  'apply_status: the provider and Whoosh error codes are stored when applied'
);

-- ---------------------------------------------------------------------------
-- crash_alert_purge (superuser). Config defaults: 30 days, 48 hours.
-- Expired: event 104 (31 days; delivery 304 goes by cascade) and counter 501 (3 days).
-- Kept: event 106 (29 days) and counter 502 (1 hour), plus everything created now.
-- ---------------------------------------------------------------------------

-- 75
select is(
  public.crash_alert_purge(),
  2,
  'purge: returns 2 (one expired event plus one expired counter)'
);

-- 76
select is(
  (select count(*) from public.crash_alert_events
     where id = 'ca000000-0000-4000-8000-000000000104'),
  0::bigint,
  'purge: the 31-day-old event is deleted'
);

-- 77
select is(
  (select count(*) from public.crash_alert_deliveries
     where id = 'ca000000-0000-4000-8000-000000000304'),
  0::bigint,
  'purge: the old event''s delivery is deleted by cascade'
);

-- 78 (101, 102, 103, 105, 106)
select is(
  (select count(*) from public.crash_alert_events),
  5::bigint,
  'purge: the other 5 events remain, including the 29-day-old one'
);

-- 79 (301, 302, 303, 305, 306)
select is(
  (select count(*) from public.crash_alert_deliveries),
  5::bigint,
  'purge: the other 5 deliveries remain'
);

-- 80 (502, plus 7 rows from successful takes: 49, 50, 53, 55, 56, 58, 59)
select is(
  (select count(*) from public.crash_alert_counters),
  8::bigint,
  'purge: the other 8 counters remain'
);

-- ---------------------------------------------------------------------------
-- Deleting the auth user cascades (superuser)
-- ---------------------------------------------------------------------------

-- 81 (103, 106)
select is(
  (select count(*) from public.crash_alert_events
     where user_id = 'ca000000-0000-4000-8000-00000000000b'),
  2::bigint,
  'before deleting user B, B has 2 events'
);

delete from auth.users where id = 'ca000000-0000-4000-8000-00000000000b';

-- 82
select is(
  (select count(*) from public.crash_alert_events
     where user_id = 'ca000000-0000-4000-8000-00000000000b'),
  0::bigint,
  'deleting user B deletes their events'
);

-- 83
select is(
  (select count(*) from public.crash_alert_deliveries
     where user_id = 'ca000000-0000-4000-8000-00000000000b'),
  0::bigint,
  'deleting user B deletes their deliveries'
);

-- 84 (B had two counters: from takes 53 and 56)
select is(
  (select count(*) from public.crash_alert_counters
     where user_id = 'ca000000-0000-4000-8000-00000000000b'),
  0::bigint,
  'deleting user B deletes their counters'
);

-- 85 (101, 102, 105)
select is(
  (select count(*) from public.crash_alert_events
     where user_id = 'ca000000-0000-4000-8000-00000000000a'),
  3::bigint,
  'deleting user B leaves user A''s events'
);

-- ---------------------------------------------------------------------------

reset role;
select * from finish();

rollback;
