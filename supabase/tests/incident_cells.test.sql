-- Tests for migration 20261024130000_incident_mapping_and_indexes.sql:
-- the public_incident_cells view (snapping, thresholds, delay, columns, grants), the new
-- near_misses constraints, and the performance indexes.
--
-- HOW TO RUN: supabase test db   (runs every file in supabase/tests/)
-- The file runs in one transaction and rolls back, so seed data comes back afterwards.

begin;

select plan(20);

-- Start from a known state: seed.sql may have loaded rides and near misses.
delete from public.rides;

-- ---------------------------------------------------------------------------
-- Fixtures (superuser). Three riders, one ride each.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email)
values
  ('c1111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'cell-u1@example.test'),
  ('c2222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'cell-u2@example.test'),
  ('c3333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'cell-u3@example.test');

insert into public.rides
  (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
values
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111',
   now() - interval '3 days', now() - interval '3 days' + interval '20 minutes', 4000, 1200, 3.3333,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}'::jsonb),
  ('d2222222-2222-4222-8222-222222222222', 'c2222222-2222-4222-8222-222222222222',
   now() - interval '3 days', now() - interval '3 days' + interval '20 minutes', 4000, 1200, 3.3333,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}'::jsonb),
  ('d3333333-3333-4333-8333-333333333333', 'c3333333-3333-4333-8333-333333333333',
   now() - interval '3 days', now() - interval '3 days' + interval '20 minutes', 4000, 1200, 3.3333,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}'::jsonb);

-- Cell A (42.360, -71.058): 3 shared, old incidents from 2 riders -> SHOWN.
--   One is rider-reported with no confidence; one is a truck.
-- Cell B (42.370, -71.060): 3 shared, old incidents from 1 rider   -> hidden (one rider).
-- Cell C (42.380, -71.070): 2 shared, old incidents from 2 riders  -> hidden (fewer than 3).
-- Cell D (42.390, -71.080): 3 riders, but one incident is 1 hour old -> hidden (delay).
-- Cell E (42.400, -71.090): 3 riders, but one incident is not shared -> hidden (opt-in).
insert into public.near_misses
  (ride_id, user_id, occurred_at, latitude, longitude, kind, confidence, source, share_publicly)
values
  -- A
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3601, -71.0581, 'vehicle', 0.8,  'detected',       true),
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3599, -71.0579, 'vehicle', null, 'rider_reported', true),
  ('d2222222-2222-4222-8222-222222222222', 'c2222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.3602, -71.0580, 'truck',   0.7,  'detected',       true),
  -- B
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3701, -71.0601, 'vehicle', 0.8,  'detected',       true),
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3702, -71.0602, 'vehicle', 0.8,  'detected',       true),
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3699, -71.0599, 'vehicle', 0.8,  'detected',       true),
  -- C
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3801, -71.0701, 'vehicle', 0.8,  'detected',       true),
  ('d2222222-2222-4222-8222-222222222222', 'c2222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.3802, -71.0702, 'vehicle', 0.8,  'detected',       true),
  -- D
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3901, -71.0801, 'vehicle', 0.8,  'detected',       true),
  ('d2222222-2222-4222-8222-222222222222', 'c2222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.3902, -71.0802, 'vehicle', 0.8,  'detected',       true),
  ('d3333333-3333-4333-8333-333333333333', 'c3333333-3333-4333-8333-333333333333', now() - interval '1 hour', 42.3899, -71.0799, 'vehicle', 0.8,  'detected',       true),
  -- E
  ('d1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.4001, -71.0901, 'vehicle', 0.8,  'detected',       true),
  ('d2222222-2222-4222-8222-222222222222', 'c2222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.4002, -71.0902, 'vehicle', 0.8,  'detected',       true),
  ('d3333333-3333-4333-8333-333333333333', 'c3333333-3333-4333-8333-333333333333', now() - interval '2 days', 42.3999, -71.0899, 'vehicle', 0.8,  'detected',       false);

-- ---------------------------------------------------------------------------
-- What anon (the website) sees
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 1
select is(
  (select count(*) from public.public_incident_cells),
  1::bigint,
  'only cell A passes snapping, the 3-incident / 2-rider threshold, the delay and the opt-in'
);

-- 2
select is(
  (select latitude from public.public_incident_cells),
  42.36::float8,
  'cell latitude is snapped to 3 decimals, not an original point'
);

-- 3
select is(
  (select longitude from public.public_incident_cells),
  -71.058::float8,
  'cell longitude is snapped to 3 decimals, not an original point'
);

-- 4
select is(
  (select incident_count from public.public_incident_cells),
  3::bigint,
  'cell A counts 3 incidents'
);

-- 5
select is(
  (select rider_reported_count from public.public_incident_cells),
  1::bigint,
  'cell A has 1 rider-reported incident'
);

-- 6
select is(
  (select detected_count from public.public_incident_cells),
  2::bigint,
  'cell A has 2 detected incidents'
);

-- 7
select is(
  (select vehicle_kinds from public.public_incident_cells),
  array['truck', 'vehicle']::text[],
  'vehicle kinds are distinct and sorted'
);

-- 8
select ok(
  (select first_month <= last_month from public.public_incident_cells),
  'first_month is not after last_month'
);

-- 9 (checks the grant directly. A write attempt is not a useful test here: the view uses
--    GROUP BY, so Postgres rejects any write with 55000 "cannot delete from view" before it
--    reaches the privilege check. The grant is what must never allow writes.)
select ok(
  not has_table_privilege('anon', 'public.public_incident_cells', 'INSERT, UPDATE, DELETE'),
  'anon has no insert, update, or delete privilege on public_incident_cells'
);

-- ---------------------------------------------------------------------------
-- Catalog checks (superuser)
-- ---------------------------------------------------------------------------

reset role;

-- 10 (exact column list: no user_id, ride_id, exact time, or confidence)
select columns_are(
  'public',
  'public_incident_cells',
  array['latitude', 'longitude', 'incident_count', 'rider_reported_count', 'detected_count',
        'vehicle_kinds', 'first_month', 'last_month'],
  'public_incident_cells exposes only snapped cells, counts, kinds, and months'
);

-- 11
select hasnt_column('public', 'public_incident_cells', 'user_id', 'public_incident_cells has no user_id');

-- 12
select hasnt_column('public', 'public_incident_cells', 'ride_id', 'public_incident_cells has no ride_id');

-- 13
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'near_misses_user_id_idx'),
  'index near_misses_user_id_idx exists (RLS filter and foreign key)'
);

-- 14
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'rides_shared_started_at_idx'),
  'partial index rides_shared_started_at_idx exists (public_rides ordering)'
);

-- 15
select ok(
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'near_misses_shared_occurred_at_idx'),
  'partial index near_misses_shared_occurred_at_idx exists (incident cells)'
);

-- ---------------------------------------------------------------------------
-- Signed-in users get no access to the view
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"c2222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;

-- 16
select throws_ok(
  $$select count(*) from public.public_incident_cells$$,
  '42501',
  null,
  'authenticated users cannot select from public_incident_cells (anon only)'
);

-- ---------------------------------------------------------------------------
-- New near_misses constraints, as the ride's owner
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

-- 17
select lives_ok(
  $$insert into public.near_misses
      (id, ride_id, occurred_at, latitude, longitude, kind, confidence, source)
    values
      ('e1111111-1111-4111-8111-111111111111', 'd1111111-1111-4111-8111-111111111111',
       now(), 42.35, -71.05, 'vehicle', null, 'rider_reported')$$,
  'a rider-reported incident with no confidence can be inserted'
);

-- 18
select is(
  (select share_publicly from public.near_misses where id = 'e1111111-1111-4111-8111-111111111111'),
  false,
  'a new incident is not shared unless the rider opts in'
);

-- 19
select throws_ok(
  $$insert into public.near_misses
      (ride_id, occurred_at, latitude, longitude, kind, confidence, source)
    values
      ('d1111111-1111-4111-8111-111111111111', now(), 42.35, -71.05, 'vehicle', null, 'detected')$$,
  '23514',
  null,
  'a detected incident must have a confidence'
);

-- 20
select throws_ok(
  $$insert into public.near_misses
      (ride_id, occurred_at, latitude, longitude, kind, confidence, source)
    values
      ('d1111111-1111-4111-8111-111111111111', now(), 42.35, -71.05, 'vehicle', 0.5, 'guess')$$,
  '23514',
  null,
  'source must be detected or rider_reported'
);

-- ---------------------------------------------------------------------------

reset role;
select * from finish();

rollback;
