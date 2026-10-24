-- Tests for migrations 20261024160000_public_crash_records.sql and
-- 20261024160100_boston_bike_crashes_mass_ave.sql:
-- the real Boston snapshot, the tables' constraints and upserts, the anon-only views, the
-- per-cell join of city crashes with Whoosh reports, and the grants.
--
-- HOW TO RUN: supabase test db   (runs every file in supabase/tests/)
-- One transaction, rolled back at the end, so the Boston snapshot comes back afterwards.

begin;

select plan(36);

-- ---------------------------------------------------------------------------
-- The real snapshot, as loaded by migration 20261024160100 (before any test data)
-- ---------------------------------------------------------------------------

-- 1 (at least: a later citywide import adds rows; it must never lose these)
select ok(
  (select count(*) from public.public_crash_records where source = 'boston_vision_zero') >= 65,
  'the Boston Vision Zero snapshot is loaded (65 Mass Ave bike crashes or more)'
);

-- 2
select is(
  (select license from public.data_sources where key = 'boston_vision_zero'),
  'Open Data Commons Public Domain Dedication and License (PDDL)',
  'the Boston source records its license'
);

-- 3
select ok(
  not exists (
    select 1 from public.public_crash_records
    where source = 'boston_vision_zero'
      and not (latitude between 42.2 and 42.45 and longitude between -71.2 and -70.95)
  ),
  'every Boston record is inside the Boston area'
);

-- ---------------------------------------------------------------------------
-- Known state for the rest of the file
-- ---------------------------------------------------------------------------

-- Every table that references data_sources has to be emptied before it.
delete from public.bike_count_days;
delete from public.bike_count_locations;
delete from public.bike_facilities;
delete from public.public_crash_records;
delete from public.data_sources;
delete from public.rides;

insert into public.data_sources (key, name, publisher, url, license, retrieved_on, data_through)
values ('test_city', 'Test City Crashes', 'Test City', 'https://example.test/crashes', 'PDDL',
        current_date, current_date - 30);

-- Cell X (42.340, -71.080): 3 bike crashes (1 and 2 years old, and 7 years old) and 1 ped crash.
-- Cell Y (42.350, -71.090): 1 bike crash, 3 years old.
-- Cell Z (42.360, -71.100): no city crashes; Whoosh reports only (below).
insert into public.public_crash_records
  (source, source_record_id, occurred_at, mode, location_type, street, cross_street_1, cross_street_2, latitude, longitude)
values
  ('test_city', 'x1', now() - interval '1 year',  'bike', 'Street', 'MAIN ST', 'A ST', 'B ST', 42.3401, -71.0801),
  ('test_city', 'x2', now() - interval '2 years', 'bike', 'Street', 'MAIN ST', 'A ST', 'B ST', 42.3399, -71.0799),
  ('test_city', 'x3', now() - interval '7 years', 'bike', 'Street', 'MAIN ST', 'A ST', 'B ST', 42.3402, -71.0802),
  ('test_city', 'x4', now() - interval '1 year',  'ped',  'Street', 'MAIN ST', 'A ST', 'B ST', 42.3400, -71.0800),
  ('test_city', 'y1', now() - interval '3 years', 'bike', 'Intersection', 'ELM ST', 'C ST', null, 42.3501, -71.0901);

-- Whoosh reports: cell X and cell Z each get 3 shared, 2-day-old incidents from 2 riders, which
-- passes the public_incident_cells thresholds.
insert into auth.users (id, aud, role, email)
values
  ('a5111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'city-u1@example.test'),
  ('a5222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'city-u2@example.test');

insert into public.rides
  (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
values
  ('b5111111-1111-4111-8111-111111111111', 'a5111111-1111-4111-8111-111111111111',
   now() - interval '3 days', now() - interval '3 days' + interval '20 minutes', 4000, 1200, 3.3333,
   '{"type":"LineString","coordinates":[[-71.08,42.34],[-71.10,42.36]]}'::jsonb),
  ('b5222222-2222-4222-8222-222222222222', 'a5222222-2222-4222-8222-222222222222',
   now() - interval '3 days', now() - interval '3 days' + interval '20 minutes', 4000, 1200, 3.3333,
   '{"type":"LineString","coordinates":[[-71.08,42.34],[-71.10,42.36]]}'::jsonb);

insert into public.near_misses
  (ride_id, user_id, occurred_at, latitude, longitude, kind, confidence, source, share_publicly)
values
  -- X
  ('b5111111-1111-4111-8111-111111111111', 'a5111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3401, -71.0801, 'vehicle', 0.8, 'detected', true),
  ('b5111111-1111-4111-8111-111111111111', 'a5111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3402, -71.0802, 'vehicle', 0.8, 'detected', true),
  ('b5222222-2222-4222-8222-222222222222', 'a5222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.3399, -71.0799, 'truck',   0.7, 'detected', true),
  -- Z
  ('b5111111-1111-4111-8111-111111111111', 'a5111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3601, -71.1001, 'vehicle', 0.8, 'detected', true),
  ('b5111111-1111-4111-8111-111111111111', 'a5111111-1111-4111-8111-111111111111', now() - interval '2 days', 42.3602, -71.1002, 'vehicle', 0.8, 'detected', true),
  ('b5222222-2222-4222-8222-222222222222', 'a5222222-2222-4222-8222-222222222222', now() - interval '2 days', 42.3599, -71.0999, 'vehicle', 0.8, 'detected', true);

-- ---------------------------------------------------------------------------
-- What anon (the website) sees
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 4
select is((select count(*) from public.public_crash_points), 5::bigint,
  'anon sees every crash point');

-- 5
select is(
  (select source_name || ' / ' || source_license from public.public_crash_points where source_record_id = 'x1'),
  'Test City Crashes / PDDL',
  'each crash point carries its source name and license for attribution'
);

-- 6
select is((select count(*) from public.public_data_sources), 1::bigint,
  'anon sees the data sources');

-- 7
select is((select count(*) from public.public_street_cells), 3::bigint,
  'street cells are the union of city cells (X, Y) and Whoosh cells (X, Z)');

-- 8
select is(
  (select city_bike_crashes from public.public_street_cells where latitude = 42.34 and longitude = -71.08),
  3::bigint,
  'cell X counts 3 city bike crashes, snapped to 3 decimals'
);

-- 9
select is(
  (select city_bike_crashes_5y from public.public_street_cells where latitude = 42.34 and longitude = -71.08),
  2::bigint,
  'cell X counts 2 bike crashes in the last 5 years'
);

-- 10
select is(
  (select city_ped_crashes from public.public_street_cells where latitude = 42.34 and longitude = -71.08),
  1::bigint,
  'cell X counts pedestrian crashes separately'
);

-- 11
select is(
  (select whoosh_reports from public.public_street_cells where latitude = 42.34 and longitude = -71.08),
  3::bigint,
  'cell X joins the 3 Whoosh reports in the same cell'
);

-- 12
select is(
  (select last_city_bike_crash_month from public.public_street_cells where latitude = 42.34 and longitude = -71.08),
  date_trunc('month', now() - interval '1 year')::date,
  'the last city crash is reported by month, not exact time'
);

-- 13
select is(
  (select whoosh_reports from public.public_street_cells where latitude = 42.35 and longitude = -71.09),
  0::bigint,
  'a city-only cell has 0 Whoosh reports, not null'
);

-- 14
select is(
  (select city_bike_crashes from public.public_street_cells where latitude = 42.36 and longitude = -71.1),
  0::bigint,
  'a Whoosh-only cell has 0 city crashes, not null'
);

-- 15
select is(
  (select whoosh_reports from public.public_street_cells where latitude = 42.36 and longitude = -71.1),
  3::bigint,
  'a Whoosh-only cell keeps its report count'
);

-- 16
select throws_ok($$select count(*) from public.public_crash_records$$, '42501', null,
  'anon cannot read the raw crash table');

-- 17
select throws_ok($$select count(*) from public.data_sources$$, '42501', null,
  'anon cannot read the raw sources table');

-- 18
select throws_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'anon1', now(), 'bike', 42.34, -71.08)$$,
  '42501', null,
  'anon cannot insert crash records'
);

-- 19 (checks the grants directly: these views are not auto-updatable, so a write attempt
--     would fail for that reason before reaching the privilege check)
select ok(
  not has_table_privilege('anon', 'public.public_crash_points', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('anon', 'public.public_data_sources', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('anon', 'public.public_street_cells', 'INSERT, UPDATE, DELETE'),
  'anon has no write privilege on any of the three views'
);

-- ---------------------------------------------------------------------------
-- Signed-in users get no access (the website never signs in; the app does not need city data)
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a5111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

-- 20
select throws_ok($$select count(*) from public.public_crash_points$$, '42501', null,
  'authenticated users cannot select public_crash_points (anon only)');

-- 21
select throws_ok($$select count(*) from public.public_street_cells$$, '42501', null,
  'authenticated users cannot select public_street_cells (anon only)');

-- 22
select throws_ok($$select count(*) from public.public_crash_records$$, '42501', null,
  'authenticated users cannot read the raw crash table');

-- ---------------------------------------------------------------------------
-- Imports run as service_role
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

-- 23
select lives_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'svc1', now() - interval '10 days', 'bike', 42.3701, -71.1101)$$,
  'service_role can insert crash records'
);

-- 24 (re-importing the same record updates it in place)
select lives_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'svc1', now() - interval '10 days', 'bike', 42.3705, -71.1105)
    on conflict (source, source_record_id) do update set
      latitude = excluded.latitude, longitude = excluded.longitude, imported_at = now()$$,
  'the importer''s upsert runs'
);

-- 25
select is(
  (select count(*) from public.public_crash_records where source = 'test_city' and source_record_id = 'svc1'),
  1::bigint,
  're-importing a record does not duplicate it'
);

-- 26
select is(
  (select latitude from public.public_crash_records where source = 'test_city' and source_record_id = 'svc1'),
  42.3705::float8,
  're-importing a record updates its fields'
);

-- ---------------------------------------------------------------------------
-- Constraints and catalog (superuser)
-- ---------------------------------------------------------------------------

reset role;

-- 27
select throws_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'bad1', now(), 'scooter', 42.34, -71.08)$$,
  '23514', null,
  'mode must be bike, ped, or mv'
);

-- 28
select throws_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'bad2', now(), 'bike', 95, -71.08)$$,
  '23514', null,
  'latitude must be in range'
);

-- 29
select throws_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('no_such_source', 'bad3', now(), 'bike', 42.34, -71.08)$$,
  '23503', null,
  'a record must belong to a known source'
);

-- 30
select throws_ok(
  $$insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
    values ('test_city', 'x1', now(), 'bike', 42.34, -71.08)$$,
  '23505', null,
  'a plain insert of an existing source record is rejected (imports must upsert)'
);

-- 31
select throws_ok(
  $$insert into public.data_sources (key, name, publisher, url, license, retrieved_on)
    values ('bad_url', 'x', 'x', 'http://example.test', 'x', current_date)$$,
  '23514', null,
  'a source URL must be https'
);

-- 32
select throws_ok(
  $$insert into public.data_sources (key, name, publisher, url, license, retrieved_on)
    values ('Bad Key!', 'x', 'x', 'https://example.test', 'x', current_date)$$,
  '23514', null,
  'a source key must be lowercase letters, digits, and underscores'
);

-- 33
select columns_are(
  'public', 'public_crash_points',
  array['source', 'source_record_id', 'occurred_at', 'mode', 'street', 'cross_street_1',
        'cross_street_2', 'latitude', 'longitude', 'source_name', 'source_license', 'source_url'],
  'public_crash_points exposes only published fields and attribution'
);

-- 34
select hasnt_column('public', 'public_crash_points', 'imported_at',
  'public_crash_points has no internal import timestamp');

-- 35
select columns_are(
  'public', 'public_street_cells',
  array['latitude', 'longitude', 'city_bike_crashes', 'city_bike_crashes_5y', 'city_ped_crashes',
        'last_city_bike_crash_month', 'whoosh_reports'],
  'public_street_cells exposes only snapped cells, counts, and a month'
);

-- 36
select ok(
  (select relrowsecurity from pg_class where oid = 'public.public_crash_records'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.data_sources'::regclass),
  'RLS is enabled on both raw tables (no policies: only the owner and service_role read them)'
);

-- ---------------------------------------------------------------------------

select * from finish();

rollback;
