-- Whoosh database performance evaluation (LOCAL DATABASE ONLY).
--
-- Loads synthetic data at a scale far above the hackathon (2,000 riders, 100,000 rides,
-- 300,000 near misses), then runs EXPLAIN (ANALYZE, BUFFERS) on the queries the app and the
-- website actually make, as the roles they make them with (anon, authenticated).
--
-- Everything runs in one transaction that ends with ROLLBACK, so no data is left behind and
-- the seed data is untouched. Never run this against the hosted project.
--
-- HOW TO RUN (from the repo root, with `supabase start` running):
--   docker exec -i supabase_db_whoosh psql -U postgres -d postgres < supabase/perf/perf_eval.sql > /tmp/whoosh-perf.txt
-- If the container name differs: docker ps --format '{{.Names}}' | grep db
-- Expect it to take under a few minutes. Paste /tmp/whoosh-perf.txt back for a readout.
--
-- WHAT TO LOOK FOR in each plan:
--   * "Execution Time" at the bottom of each block.
--   * "Index Scan" / "Index Only Scan" on the indexes from the migrations, versus
--     "Seq Scan" on rides or near_misses (a full table read).
--   * "Rows Removed by Filter" in the hundreds of thousands means an index is not being used.
-- The synthetic data is uniform and the machine is a laptop, so treat the numbers as relative
-- (which queries are slow and why), not as production latency.

\timing on
\set ON_ERROR_STOP on

begin;

\echo '=== 0. Clear existing rows (restored by the final rollback) ==='
delete from public.rides;

-- ---------------------------------------------------------------------------
\echo '=== 1. Load synthetic data ==='
-- ---------------------------------------------------------------------------

-- 2,000 riders. Deterministic ids so queries below can pick one.
insert into auth.users (id, aud, role, email)
select
  ('ee000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'perf-' || i || '@example.test'
from generate_series(1, 2000) as i;

-- 100,000 rides, 50 per rider, spread over 90 days, 10% shared.
-- Each route is a 200-point LineString, close to a real 20-minute ride, so row size and
-- TOAST storage are realistic for the public_rides payload.
with route as (
  select jsonb_build_object(
    'type', 'LineString',
    'coordinates', (
      select jsonb_agg(jsonb_build_array(-71.06 + k * 0.0001, 42.36 + k * 0.00005))
      from generate_series(1, 200) as k
    )
  ) as geojson
)
insert into public.rides
  (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route,
   app_version, share_publicly)
select
  ('7e000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
  ('ee000000-0000-4000-8000-' || lpad((((i - 1) % 2000) + 1)::text, 12, '0'))::uuid,
  now() - make_interval(days => i % 90, mins => i % 1440),
  now() - make_interval(days => i % 90, mins => i % 1440) + interval '20 minutes',
  4000, 1200, 3.333,
  route.geojson,
  '0.1.0',
  (i % 10 = 0)
from generate_series(1, 100000) as i, route;

-- 300,000 near misses, 3 per ride, owned by the ride's rider, clustered over a 6 km x 6 km
-- area of Boston (about 3,600 grid cells), 10% shared, 20% rider-reported.
insert into public.near_misses
  (ride_id, user_id, occurred_at, latitude, longitude, kind, confidence, position_hint,
   source, share_publicly)
select
  ('7e000000-0000-4000-8000-' || lpad((((j - 1) % 100000) + 1)::text, 12, '0'))::uuid,
  ('ee000000-0000-4000-8000-' || lpad((((((j - 1) % 100000)) % 2000) + 1)::text, 12, '0'))::uuid,
  now() - make_interval(days => (((j - 1) % 100000) + 1) % 90, mins => j % 1440),
  42.33 + random() * 0.06,
  -71.10 + random() * 0.06,
  (array['vehicle', 'car', 'truck', 'bus'])[1 + (j % 4)],
  case when j % 5 = 0 then null else 0.5 + random() * 0.5 end,
  (array['left', 'center', 'right'])[1 + (j % 3)],
  case when j % 5 = 0 then 'rider_reported' else 'detected' end,
  (j % 10 = 0)
from generate_series(1, 300000) as j;

analyze public.rides;
analyze public.near_misses;

\echo '=== Table sizes (data + indexes + TOAST) ==='
select
  c.relname as table_name,
  pg_size_pretty(pg_total_relation_size(c.oid)) as total_size,
  pg_size_pretty(pg_indexes_size(c.oid)) as index_size
from pg_class c
where c.oid in ('public.rides'::regclass, 'public.near_misses'::regclass);

-- ---------------------------------------------------------------------------
\echo '=== Q1. Website: latest 50 shared rides (role anon, view public_rides) ==='
-- Expect: index scan on rides_shared_started_at_idx, no sort of 10,000 rows.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
explain (analyze, buffers)
select id, started_at, distance_m, active_duration_s, avg_speed_mps, route
from public.public_rides
order by started_at desc
limit 50;

-- ---------------------------------------------------------------------------
\echo '=== Q2. Website: incident cells (role anon, view public_incident_cells) ==='
-- Aggregates every shared incident older than 24 h on each read. This is the query most
-- likely to be slow; the contract's fallback is a materialized view.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
select latitude, longitude, incident_count, rider_reported_count, detected_count,
       vehicle_kinds, first_month, last_month
from public.public_incident_cells
order by incident_count desc
limit 500;

\echo '=== Q2b. How many cells the website would receive ==='
select count(*) as visible_cells from public.public_incident_cells;

-- ---------------------------------------------------------------------------
\echo '=== Q3. App: a rider''s own latest 50 rides (role authenticated, RLS) ==='
-- Expect: index scan on rides_user_id_started_at_idx; about 50 rows, not 100,000.
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims',
  '{"sub":"ee000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers)
select id, started_at, distance_m
from public.rides
order by started_at desc
limit 50;

-- ---------------------------------------------------------------------------
\echo '=== Q4. App: all of a rider''s own near misses (role authenticated, RLS) ==='
-- Expect: index scan on near_misses_user_id_idx (added for this; without it, a full scan).
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
select count(*) from public.near_misses;

-- ---------------------------------------------------------------------------
\echo '=== Q5. App: near misses for one ride (role authenticated, RLS) ==='
-- Expect: index scan on near_misses_ride_id_idx.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
select id, occurred_at, kind, confidence
from public.near_misses
where ride_id = '7e000000-0000-4000-8000-000000000001';

-- ---------------------------------------------------------------------------
\echo '=== Q6. App sync: upsert one ride by id (role authenticated, RLS insert + update checks) ==='
-- The app's upload path. Expect: primary-key lookup, a few ms at most.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
insert into public.rides
  (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
values
  ('7e000000-0000-4000-8000-000000000001', now() - interval '1 hour', now(),
   4100, 1210, 3.388,
   '{"type":"LineString","coordinates":[[-71.06,42.36],[-71.05,42.37]]}'::jsonb)
-- A re-upload replaces every field. Updating only some of them can leave the row inconsistent
-- (for example active time longer than the stored start-to-end span), which the
-- rides_active_within_elapsed constraint rejects.
on conflict (id) do update
  set started_at = excluded.started_at,
      ended_at = excluded.ended_at,
      distance_m = excluded.distance_m,
      active_duration_s = excluded.active_duration_s,
      avg_speed_mps = excluded.avg_speed_mps,
      route = excluded.route;

-- ---------------------------------------------------------------------------
\echo '=== Q7. App: insert one near miss (role authenticated, RLS ride-ownership check) ==='
-- The with-check runs an exists() lookup on rides. Expect: primary-key lookup.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
insert into public.near_misses
  (ride_id, occurred_at, latitude, longitude, kind, confidence, source)
values
  ('7e000000-0000-4000-8000-000000000001', now(), 42.36, -71.06, 'vehicle', 0.9, 'detected');

-- ---------------------------------------------------------------------------
\echo '=== Q8. App: delete one ride, cascading to its near misses (role authenticated, RLS) ==='
-- Expect: primary-key delete, plus the cascade using near_misses_ride_id_idx.
-- ---------------------------------------------------------------------------
explain (analyze, buffers)
delete from public.rides where id = '7e000000-0000-4000-8000-000000002001';

reset role;
rollback;

\echo '=== Done. All synthetic data was rolled back. ==='
