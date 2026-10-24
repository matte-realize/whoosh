-- Tests for migration 20261024140000_input_limits_and_public_stats.sql:
-- route validation, ride and near-miss limits, and the public_stats view.
--
-- HOW TO RUN: supabase test db   (runs every file in supabase/tests/)
-- One transaction, rolled back at the end.

begin;

select plan(27);

delete from public.rides;

insert into auth.users (id, aud, role, email)
values
  ('f1111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'limits-u1@example.test'),
  ('f2222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'limits-u2@example.test'),
  ('f3333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'limits-u3@example.test');

-- ---------------------------------------------------------------------------
-- Route validation, through the function (superuser)
-- ---------------------------------------------------------------------------

-- 1
select ok(public.is_valid_route('{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}'),
  'a 2-point route is valid');
-- 2
select ok(public.is_valid_route('{"type":"LineString","coordinates":[[-71.06,42.36,12.5],[-71.05,42.37,13]]}'),
  'points with altitude are valid');
-- 3
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[[-71.06,42.36]]}'),
  'a 1-point route is rejected');
-- 4
select ok(not public.is_valid_route(
    jsonb_build_object('type', 'LineString', 'coordinates',
      (select jsonb_agg(jsonb_build_array(-71.0, 42.0)) from generate_series(1, 10001)))),
  'a route with 10,001 points is rejected');
-- 5
select ok(public.is_valid_route(
    jsonb_build_object('type', 'LineString', 'coordinates',
      (select jsonb_agg(jsonb_build_array(-71.0, 42.0)) from generate_series(1, 10000)))),
  'a route with exactly 10,000 points is valid');
-- 6
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[[-200,42.36],[-71.05,42.37]]}'),
  'longitude out of range is rejected');
-- 7
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[[-71.06,95],[-71.05,42.37]]}'),
  'latitude out of range is rejected');
-- 8
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[["-71.06",42.36],[-71.05,42.37]]}'),
  'a coordinate given as a string is rejected');
-- 9
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[[-71.06],[-71.05,42.37]]}'),
  'a point with one number is rejected');
-- 10
select ok(not public.is_valid_route('{"type":"LineString","coordinates":[[-71.06,42.36,1,2],[-71.05,42.37]]}'),
  'a point with four numbers is rejected');
-- 11
select ok(not public.is_valid_route('{"type":"LineString","coordinates":{"a":1}}'),
  'coordinates that are not an array are rejected');
-- 12
select ok(not public.is_valid_route('{"type":"Point","coordinates":[-71.06,42.36]}'),
  'a non-LineString geometry is rejected');
-- 13
select ok(not public.is_valid_route('[1,2,3]'),
  'a JSON array instead of an object is rejected');

-- ---------------------------------------------------------------------------
-- Ride limits, as a signed-in rider (the real upload path)
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"f1111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
set local role authenticated;

-- 14
select lives_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version)
    values
      ('a1111111-1111-4111-8111-111111111111', '2026-10-20 12:00+00', '2026-10-20 12:20+00',
       4000, 1150, 3.48,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}', '0.1.0')$$,
  'a normal ride uploads'
);

-- 15
select throws_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('a2222222-2222-4222-8222-222222222222', '2026-10-20 12:00+00', '2026-10-20 12:20+00',
       4000, 1150, 3.48,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-971.05,42.37]]}')$$,
  '23514', null,
  'a ride with an invalid route point is rejected'
);

-- 16
select throws_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('a3333333-3333-4333-8333-333333333333', '2026-10-20 12:00+00', '2026-10-20 12:20+00',
       4000, 1150, 55,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}')$$,
  '23514', null,
  'average speed above 40 m/s is rejected'
);

-- 17
select throws_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('a4444444-4444-4444-8444-444444444444', '2026-10-20 12:00+00', '2026-10-20 12:20+00',
       4000, 5000, 0.8,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}')$$,
  '23514', null,
  'active time longer than the ride''s wall-clock span is rejected'
);

-- 18
select throws_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('a5555555-5555-4555-8555-555555555555', '2026-10-20 12:00+00', '2026-10-23 12:00+00',
       4000, 1150, 3.48,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}')$$,
  '23514', null,
  'a ride spanning more than 48 hours is rejected'
);

-- 19
select throws_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version)
    values
      ('a6666666-6666-4666-8666-666666666666', '2026-10-20 12:00+00', '2026-10-20 12:20+00',
       4000, 1150, 3.48,
       '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}',
       repeat('x', 33))$$,
  '23514', null,
  'an app_version longer than 32 characters is rejected'
);

-- ---------------------------------------------------------------------------
-- Near-miss limits, as the same rider
-- ---------------------------------------------------------------------------

-- 20
select throws_ok(
  $$insert into public.near_misses
      (ride_id, occurred_at, latitude, longitude, kind, confidence)
    values
      ('a1111111-1111-4111-8111-111111111111', '2026-10-20 12:05+00', 142.36, -71.06, 'vehicle', 0.9)$$,
  '23514', null,
  'a near miss with latitude out of range is rejected'
);

-- 21
select throws_ok(
  $$insert into public.near_misses
      (ride_id, occurred_at, latitude, longitude, kind, confidence)
    values
      ('a1111111-1111-4111-8111-111111111111', '2026-10-20 12:05+00', 42.36, -71.06, '', 0.9)$$,
  '23514', null,
  'a near miss with an empty kind is rejected'
);

-- ---------------------------------------------------------------------------
-- public_stats
-- ---------------------------------------------------------------------------

reset role;

-- Shared rides: two by u1, one by u2. One private ride by u3 must not count.
insert into public.rides
  (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, share_publicly)
values
  ('b1111111-1111-4111-8111-111111111111', 'f1111111-1111-4111-8111-111111111111',
   '2026-10-21 12:00+00', '2026-10-21 12:20+00', 1000, 600, 1.667,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}', true),
  ('b2222222-2222-4222-8222-222222222222', 'f1111111-1111-4111-8111-111111111111',
   '2026-10-22 12:00+00', '2026-10-22 12:20+00', 2000, 700, 2.857,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}', true),
  ('b3333333-3333-4333-8333-333333333333', 'f2222222-2222-4222-8222-222222222222',
   '2026-10-23 12:00+00', '2026-10-23 12:20+00', 3000, 800, 3.75,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}', true),
  ('b4444444-4444-4444-8444-444444444444', 'f3333333-3333-4333-8333-333333333333',
   '2026-10-23 13:00+00', '2026-10-23 13:20+00', 9000, 900, 10,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}', false);

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 22
select is((select shared_rides from public.public_stats), 3::bigint,
  'public_stats counts only shared rides');
-- 23
select is((select total_distance_m from public.public_stats), 6000::float8,
  'public_stats sums distance over shared rides only');
-- 24
select is((select riders from public.public_stats), null::bigint,
  'the rider count is hidden when fewer than 3 riders have shared rides');

-- Third rider shares a ride: now the count may be shown.
reset role;
update public.rides set share_publicly = true where id = 'b4444444-4444-4444-8444-444444444444';
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 25
select is((select riders from public.public_stats), 3::bigint,
  'the rider count is shown once 3 riders have shared rides');

reset role;

-- 26
select columns_are('public', 'public_stats',
  array['shared_rides', 'total_distance_m', 'total_active_duration_s', 'riders',
        'mapped_incidents', 'incident_cells'],
  'public_stats exposes only totals');

-- 27
select set_config('request.jwt.claims',
  '{"sub":"f2222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$select * from public.public_stats$$, '42501', null,
  'authenticated users cannot read public_stats (the website reads as anon)');

reset role;
select * from finish();

rollback;
