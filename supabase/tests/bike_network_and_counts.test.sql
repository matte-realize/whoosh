-- Tests for migrations 20261024170000_bike_network_and_counts.sql, 20261024170100 (Mass Ave
-- bike network) and 20261024170200 (Mass Ave bike counts): the real snapshots, the distance
-- helper, crash-to-lane matching, the count averages, constraints, and grants.
--
-- HOW TO RUN: supabase test db   (runs every file in supabase/tests/)
-- One transaction, rolled back at the end, so the real snapshots come back afterwards.

begin;

select plan(48);

-- ---------------------------------------------------------------------------
-- The real snapshots (before any test data)
-- ---------------------------------------------------------------------------

-- 1 (at least: a citywide import adds rows; it must never lose these)
select ok(
  (select count(*) from public.bike_facilities where source = 'boston_bike_network_2024') >= 62,
  'the Boston bike network snapshot is loaded (62 Mass Ave segments or more)'
);

-- 2
select ok(
  (select count(*) from public.bike_count_days where source = 'boston_bike_counts') >= 180
  and (select count(*) from public.bike_count_locations where source = 'boston_bike_counts') >= 4,
  'the Boston bike count snapshot is loaded (4 Mass Ave counters, 180 days or more)'
);

-- 3 (real data through the real views: every Mass Ave bike crash lies on a mapped lane segment)
select is(
  (select count(*) from public.public_crash_facility_context x
     join public.public_crash_records c using (source, source_record_id)
    where c.source = 'boston_vision_zero' and c.street = 'MASSACHUSETTS AVE' and x.facility_code is not null),
  (select count(*) from public.public_crash_records
    where source = 'boston_vision_zero' and street = 'MASSACHUSETTS AVE' and mode = 'bike'),
  'every Mass Ave bike crash in the snapshot is matched to a Mass Ave lane segment within 25 m'
);

-- 4 (a fixed past year, so a later import of new count days can't change it)
select results_eq(
  $$select days_counted, avg_daily_bikes, min_daily_bikes, max_daily_bikes, avg_daily_motor_vehicles
      from public.public_bike_count_years
     where source = 'boston_bike_counts' and location_id = '44' and year = 2025$$,
  $$values (8::bigint, 4589, 2900, 6045, 21526)$$,
  'Mass Ave north of Back Street, 2025: 8 full days, 4,589 bikes a day on average'
);

-- ---------------------------------------------------------------------------
-- The distance helper (superuser)
-- ---------------------------------------------------------------------------

-- 5
select ok(
  public.segment_distance_m(42.34, -71.0795, 42.34, -71.08, 42.34, -71.079) < 0.01,
  'a point on the segment is 0 m from it'
);

-- 6 (past the end: the distance is to the nearest end, 0.001 degrees of longitude)
select ok(
  abs(public.segment_distance_m(42.34, -71.08, 42.34, -71.079, 42.34, -71.078) - 82.28) < 0.1,
  'a point beyond the end is measured to the end (about 82.3 m)'
);

-- 7 (zero-length segment: 0.001 degrees of latitude)
select ok(
  abs(public.segment_distance_m(42.34, -71.08, 42.341, -71.08, 42.341, -71.08) - 110.57) < 0.1,
  'a zero-length segment is measured as a point (about 110.6 m)'
);

-- ---------------------------------------------------------------------------
-- Known state for the rest of the file
-- ---------------------------------------------------------------------------

delete from public.bike_count_days;
delete from public.bike_count_locations;
delete from public.bike_facilities;
delete from public.public_crash_records;
delete from public.data_sources;

insert into public.data_sources (key, name, publisher, url, license, retrieved_on)
values
  ('test_net',    'Test Network', 'Test City', 'https://example.test/net',     'PDDL', current_date),
  ('test_counts', 'Test Counts',  'Test City', 'https://example.test/counts',  'PDDL', current_date),
  ('test_city',   'Test Crashes', 'Test City', 'https://example.test/crashes', 'PDDL', current_date);

-- f1: separated lane installed 2020, east-west along latitude 42.34.
-- f2: painted lane installed 2011, north-south along longitude -71.09.
-- z1, z2: two painted segments meeting at (42.36, -71.10), to test the tie-break.
insert into public.bike_facilities (source, source_record_id, street, facility_code, install_year, route)
values
  ('test_net', 'f1', 'MAIN ST', 'SBL', 2020, '{"type":"LineString","coordinates":[[-71.0800,42.3400],[-71.0790,42.3400]]}'),
  ('test_net', 'f2', 'ELM ST',  'BL',  2011, '{"type":"LineString","coordinates":[[-71.0900,42.3500],[-71.0900,42.3505],[-71.0900,42.3510]]}'),
  ('test_net', 'z2', 'OAK ST',  'BL',  2015, '{"type":"LineString","coordinates":[[-71.1000,42.3600],[-71.1000,42.3610]]}'),
  ('test_net', 'z1', 'OAK ST',  'BFBL', 2015, '{"type":"LineString","coordinates":[[-71.1010,42.3600],[-71.1000,42.3600]]}');

insert into public.public_crash_records (source, source_record_id, occurred_at, mode, latitude, longitude)
values
  ('test_city', 'c1', '2018-05-01T12:00:00Z', 'bike', 42.3401, -71.0795),  -- 11 m from f1, before it was built
  ('test_city', 'c2', '2022-05-01T12:00:00Z', 'bike', 42.3400, -71.0795),  -- on f1, after it was built
  ('test_city', 'c3', '2020-05-01T12:00:00Z', 'bike', 42.3400, -71.0795),  -- on f1, the year it was built
  ('test_city', 'c4', '2022-05-01T12:00:00Z', 'bike', 42.3450, -71.0850),  -- no lane nearby
  ('test_city', 'c5', '2022-05-01T12:00:00Z', 'ped',  42.3400, -71.0795),  -- pedestrian: not in the view
  ('test_city', 'c6', '2015-05-01T12:00:00Z', 'bike', 42.3505, -71.0899),  -- 8 m from f2's middle point
  ('test_city', 'c7', '2022-05-01T12:00:00Z', 'bike', 42.3600, -71.1000),  -- where z1 and z2 meet
  ('test_city', 'c8', '2022-05-01T12:00:00Z', 'bike', 42.3403, -71.0795);  -- 33 m from f1: too far

-- Counter k1: two full days in 2024 (100 and 201 bikes), one 12-hour day (ignored), one full
-- day in 2025. Counter k2: only a partial day, so it has no public averages.
insert into public.bike_count_locations (source, location_id, name, latitude, longitude)
values
  ('test_counts', 'k1', 'Main St east of A St', 42.3400, -71.0795),
  ('test_counts', 'k2', 'Elm St north of B St', 42.3505, -71.0900);

insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes, motor_vehicles)
values
  ('test_counts', 'k1', '2024-06-01', 24, 100,  900),
  ('test_counts', 'k1', '2024-06-02', 24, 201,  1000),
  ('test_counts', 'k1', '2024-06-03', 12, 5000, 5000),
  ('test_counts', 'k1', '2025-03-01', 24, 300,  2700),
  ('test_counts', 'k2', '2025-03-01', 10, 40,   400);

-- ---------------------------------------------------------------------------
-- What anon (the website) sees
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 8
select is((select count(*) from public.public_bike_facilities), 4::bigint,
  'anon sees every lane segment');

-- 9
select results_eq(
  $$select facility_label, protection, install_year::integer, source_name
      from public.public_bike_facilities where source_record_id = 'f1'$$,
  $$values ('Separated bike lane', 'separated', 2020, 'Test Network')$$,
  'a segment carries its label, protection class, install year, and source'
);

-- 10
select is(
  (select route -> 'coordinates' -> 1 ->> 1 from public.public_bike_facilities where source_record_id = 'f2'),
  '42.3505',
  'segment geometry is passed through as GeoJSON'
);

-- 11
select is((select count(*) from public.public_crash_facility_context), 7::bigint,
  'the crash context view has one row per city bike crash (pedestrian crashes excluded)');

-- 12
select results_eq(
  $$select facility_source_record_id, protection, facility_status
      from public.public_crash_facility_context where source_record_id = 'c1'$$,
  $$values ('f1', 'separated', 'before_install')$$,
  'a crash before the lane''s install year is marked before_install'
);

-- 13
select ok(
  (select distance_m between 11.0 and 11.2 from public.public_crash_facility_context where source_record_id = 'c1'),
  'the distance to the lane is reported in meters (about 11.1 m)'
);

-- 14
select is(
  (select facility_status from public.public_crash_facility_context where source_record_id = 'c2'),
  'in_place',
  'a crash after the install year is marked in_place'
);

-- 15
select is(
  (select facility_status from public.public_crash_facility_context where source_record_id = 'c3'),
  'install_year',
  'a crash in the install year is marked install_year (cannot tell)'
);

-- 16
select ok(
  (select facility_code is null and facility_status is null and distance_m is null
     from public.public_crash_facility_context where source_record_id = 'c4'),
  'a crash with no lane nearby has no facility'
);

-- 17
select results_eq(
  $$select facility_source_record_id, facility_status
      from public.public_crash_facility_context where source_record_id = 'c6'$$,
  $$values ('f2', 'in_place')$$,
  'a lane with several points is matched on the right piece'
);

-- 18
select is(
  (select facility_source_record_id from public.public_crash_facility_context where source_record_id = 'c7'),
  'z1',
  'a tie between two segments goes to the lower record id'
);

-- 19
select ok(
  (select facility_code is null from public.public_crash_facility_context where source_record_id = 'c8'),
  'a lane 33 m away is not matched (limit 25 m)'
);

-- 20
select results_eq(
  $$select year, days_counted, avg_daily_bikes, min_daily_bikes, max_daily_bikes, avg_daily_motor_vehicles
      from public.public_bike_count_years where location_id = 'k1' order by year$$,
  $$values (2024, 2::bigint, 151, 100, 201, 950), (2025, 1::bigint, 300, 300, 300, 2700)$$,
  'yearly averages use full days only, rounded half up (150.5 -> 151)'
);

-- 21
select is((select count(*) from public.public_bike_count_years where location_id = 'k2'), 0::bigint,
  'a counter with only partial days has no yearly figures');

-- 22
select results_eq(
  $$select days_counted, first_year, last_year, latest_year_days, latest_avg_daily_bikes,
           latest_avg_daily_motor_vehicles, latest_bike_share
      from public.public_bike_count_locations where location_id = 'k1'$$,
  $$values (3, 2024, 2025, 1::bigint, 300, 2700, 0.1::float8)$$,
  'a counter shows its span and its latest year; bike share is bikes over all vehicles'
);

-- 23
select is((select count(*) from public.public_bike_count_locations), 1::bigint,
  'counters with no full day are left out');

-- 24
select is((select source_url from public.public_bike_count_locations where location_id = 'k1'),
  'https://example.test/counts', 'a counter carries its source for attribution');

-- 25
select throws_ok($$select count(*) from public.bike_facilities$$, '42501', null,
  'anon cannot read the raw lane table');

-- 26
select throws_ok($$select count(*) from public.bike_count_days$$, '42501', null,
  'anon cannot read the raw count table');

-- 27
select throws_ok($$select count(*) from public.bike_count_locations$$, '42501', null,
  'anon cannot read the raw counter table');

-- 28
select throws_ok($$select count(*) from public.bike_facility_types$$, '42501', null,
  'anon cannot read the facility type table directly (the views carry labels)');

-- 29 (views check function privileges against the caller, so the crash context view needs this;
--     the function is arithmetic only)
select ok(
  has_function_privilege('anon', 'public.segment_distance_m(float8, float8, float8, float8, float8, float8)', 'execute')
  and not has_function_privilege('authenticated', 'public.segment_distance_m(float8, float8, float8, float8, float8, float8)', 'execute'),
  'anon may call the distance helper (the crash context view needs it); authenticated may not'
);

-- 30
select ok(
  not has_table_privilege('anon', 'public.public_bike_facilities', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('anon', 'public.public_bike_count_years', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('anon', 'public.public_bike_count_locations', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('anon', 'public.public_crash_facility_context', 'INSERT, UPDATE, DELETE'),
  'anon has no write privilege on any of the four views'
);

-- ---------------------------------------------------------------------------
-- Signed-in users get no access
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"a6111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

-- 31
select throws_ok($$select count(*) from public.public_bike_facilities$$, '42501', null,
  'authenticated users cannot select public_bike_facilities (anon only)');

-- 32
select throws_ok($$select count(*) from public.public_crash_facility_context$$, '42501', null,
  'authenticated users cannot select public_crash_facility_context (anon only)');

-- 33
select throws_ok($$select count(*) from public.bike_count_days$$, '42501', null,
  'authenticated users cannot read the raw count table');

-- ---------------------------------------------------------------------------
-- Imports run as service_role
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

-- 34 (the route check calls is_valid_route, which service_role may execute)
select lives_ok(
  $$insert into public.bike_facilities (source, source_record_id, street, facility_code, install_year, route)
    values ('test_net', 's1', 'PINE ST', 'SLM', 2019, '{"type":"LineString","coordinates":[[-71.05,42.33],[-71.051,42.331]]}')
    on conflict (source, source_record_id) do update set install_year = excluded.install_year$$,
  'service_role can upsert a lane segment'
);

-- 35
select lives_ok(
  $$insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes, motor_vehicles)
    values ('test_counts', 'k1', '2025-03-01', 24, 320, 2700)
    on conflict (source, location_id, count_date) do update set bikes = excluded.bikes$$,
  'service_role can upsert a count day'
);

-- 36
select is(
  (select bikes from public.bike_count_days where location_id = 'k1' and count_date = '2025-03-01'),
  320,
  're-importing a count day updates it in place'
);

-- ---------------------------------------------------------------------------
-- Constraints and catalog (superuser)
-- ---------------------------------------------------------------------------

reset role;

-- 37
select throws_ok(
  $$insert into public.bike_facilities (source, source_record_id, facility_code, route)
    values ('test_net', 'bad1', 'XYZ', '{"type":"LineString","coordinates":[[-71.05,42.33],[-71.051,42.331]]}')$$,
  '23503', null,
  'a segment must use a known facility code'
);

-- 38
select throws_ok(
  $$insert into public.bike_facilities (source, source_record_id, facility_code, route)
    values ('test_net', 'bad2', 'BL', '{"type":"LineString","coordinates":[[-71.05,42.33]]}')$$,
  '23514', null,
  'a segment needs a valid LineString (at least 2 points)'
);

-- 39
select throws_ok(
  $$insert into public.bike_facilities (source, source_record_id, facility_code, install_year, route)
    values ('test_net', 'bad3', 'BL', 1900, '{"type":"LineString","coordinates":[[-71.05,42.33],[-71.051,42.331]]}')$$,
  '23514', null,
  'an install year must be plausible'
);

-- 40
select throws_ok(
  $$insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes)
    values ('test_counts', 'k1', '2025-04-01', 25, 10)$$,
  '23514', null,
  'a day has at most 24 counted hours'
);

-- 41
select throws_ok(
  $$insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes)
    values ('test_counts', 'k1', '2025-04-02', 24, -1)$$,
  '23514', null,
  'a bike count cannot be negative'
);

-- 42
select throws_ok(
  $$insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes)
    values ('test_counts', 'nope', '2025-04-03', 24, 10)$$,
  '23503', null,
  'a count day must belong to a known counter'
);

-- 43
select throws_ok(
  $$insert into public.bike_count_days (source, location_id, count_date, hours_counted, bikes)
    values ('test_counts', 'k1', '2024-06-01', 24, 10)$$,
  '23505', null,
  'a plain insert of an existing day is rejected (imports must upsert)'
);

-- 44
select columns_are(
  'public', 'public_bike_facilities',
  array['source', 'source_record_id', 'street', 'facility_code', 'facility_label', 'protection',
        'install_year', 'route', 'source_name', 'source_license', 'source_url'],
  'public_bike_facilities exposes only published fields, labels, and attribution'
);

-- 45
select columns_are(
  'public', 'public_bike_count_locations',
  array['source', 'location_id', 'name', 'latitude', 'longitude', 'days_counted', 'first_year',
        'last_year', 'latest_year_days', 'latest_avg_daily_bikes', 'latest_avg_daily_motor_vehicles',
        'latest_bike_share', 'source_name', 'source_license', 'source_url'],
  'public_bike_count_locations exposes counters, sample sizes, averages, and attribution'
);

-- 46
select columns_are(
  'public', 'public_crash_facility_context',
  array['source', 'source_record_id', 'occurred_at', 'facility_source_record_id', 'facility_code',
        'protection', 'install_year', 'distance_m', 'facility_status'],
  'public_crash_facility_context exposes the match and nothing internal'
);

-- 47
select is(
  (select count(*) from public.bike_facility_types),
  17::bigint,
  'all 17 facility codes in the 2024 network are defined'
);

-- 48
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.bike_facility_types'::regclass, 'public.bike_facilities'::regclass,
                  'public.bike_count_locations'::regclass, 'public.bike_count_days'::regclass)),
  'RLS is enabled on all four raw tables'
);

-- ---------------------------------------------------------------------------

select * from finish();

rollback;
