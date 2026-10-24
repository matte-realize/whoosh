-- seed.sql: local/dev sample data for Whoosh. Runs after migrations on `supabase db reset`.
--
-- WARNING: LOCAL/DEV ONLY. This file inserts a fake user into auth.users.
-- It must NEVER be applied to the real (remote) Supabase project. Do not run `supabase db push`
-- with this data, and do not paste it into the remote SQL editor.
--
-- Contents: three fake seed users and 6 rides in Austin, TX (3 shared, one per user; 3 private),
-- 10 near_misses. The first 4 are private; the last 6 are shared and form two incident areas
-- that pass the public_incident_cells thresholds.
--
-- Conventions (see .kiro/team/supabase-contract.md):
--   * SI units: meters, seconds, meters/second. Timestamps are UTC.
--   * route is a GeoJSON LineString in [longitude, latitude] order, already privacy-trimmed
--     (the ~160 m end segments are not included in the route).
--   * distance_m is the full-ride distance before trimming, so it is about 320 m longer than the
--     stored route polyline. All distances are approximate (hand-placed points, haversine).
--   * avg_speed_mps = distance_m / active_duration_s, rounded to 3 decimals.
--   * The same data lives in web/fixtures/rides.json. Keep the two files in sync. The two
--     rider-reported near misses (no confidence score) are left out of that file, because the
--     website's per-ride markers need a score.

-- Fake user so rides.user_id and near_misses.user_id have a valid auth.users parent.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values (
  '00000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'seed@example.test',
  '2026-10-10T00:00:00Z',
  '2026-10-10T00:00:00Z'
)
on conflict do nothing;

-- Rides

-- Lady Bird Lake trail, east along the water (SHARED)
-- polyline ~3771 m; distance_m adds the trimmed ends.

insert into rides (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version, share_publicly)
values (
  '10000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  '2026-10-22T22:30:00Z',
  '2026-10-22T22:45:00Z',
  4090,
  840,
  4.869,
  '{"type":"LineString","coordinates":[[-97.753,30.2655],[-97.7498,30.2662],[-97.7465,30.2668],[-97.743,30.2672],[-97.7395,30.2679],[-97.736,30.2688],[-97.7325,30.2694],[-97.729,30.2701],[-97.7255,30.2712],[-97.722,30.272],[-97.7185,30.2731],[-97.715,30.2738]]}'::jsonb,
  '0.1.0',
  true
)
on conflict do nothing;

-- Congress Ave, downtown to the Capitol
-- polyline ~2925 m; distance_m adds the trimmed ends.

insert into rides (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version, share_publicly)
values (
  '10000000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  '2026-10-19T13:10:00Z',
  '2026-10-19T13:22:00Z',
  3250,
  700,
  4.643,
  '{"type":"LineString","coordinates":[[-97.7431,30.264],[-97.743,30.2672],[-97.7429,30.2705],[-97.7428,30.2738],[-97.7427,30.2771],[-97.7426,30.2804],[-97.7425,30.2837],[-97.7424,30.287],[-97.7423,30.2903]]}'::jsonb,
  '0.1.0',
  false
)
on conflict do nothing;

-- UT campus loop
-- polyline ~3029 m; distance_m adds the trimmed ends.

insert into rides (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version, share_publicly)
values (
  '10000000-0000-4000-8000-000000000003',
  '00000000-0000-0000-0000-000000000001',
  '2026-10-15T20:05:00Z',
  '2026-10-15T20:17:00Z',
  3350,
  680,
  4.926,
  '{"type":"LineString","coordinates":[[-97.738,30.285],[-97.7345,30.2852],[-97.731,30.2856],[-97.7308,30.289],[-97.7312,30.2925],[-97.735,30.2927],[-97.739,30.2924],[-97.7393,30.289],[-97.7385,30.286],[-97.738,30.2851]]}'::jsonb,
  '0.1.0',
  false
)
on conflict do nothing;

-- East Austin evening loop
-- polyline ~3788 m; distance_m adds the trimmed ends.

insert into rides (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version, share_publicly)
values (
  '10000000-0000-4000-8000-000000000004',
  '00000000-0000-0000-0000-000000000001',
  '2026-10-12T23:15:00Z',
  '2026-10-12T23:31:00Z',
  4110,
  900,
  4.567,
  '{"type":"LineString","coordinates":[[-97.726,30.263],[-97.7225,30.2645],[-97.719,30.2662],[-97.716,30.2685],[-97.714,30.2712],[-97.7165,30.274],[-97.72,30.2755],[-97.7235,30.2738],[-97.7262,30.2712],[-97.728,30.268],[-97.727,30.265]]}'::jsonb,
  '0.1.0',
  false
)
on conflict do nothing;

-- Near misses: kind is always 'vehicle'; lat/lon are points on the ride's route.

insert into near_misses (id, ride_id, user_id, occurred_at, latitude, longitude, kind, confidence, position_hint)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', '2026-10-22T22:34:10Z', 30.2672, -97.743, 'vehicle', 0.87, 'left'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', '2026-10-22T22:37:40Z', 30.2694, -97.7325, 'vehicle', 0.74, 'right'),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', '2026-10-22T22:41:15Z', 30.272, -97.722, 'vehicle', 0.62, null),
  ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000001', '2026-10-19T13:16:30Z', 30.2771, -97.7427, 'vehicle', 0.91, 'center')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- More local riders, so the website's live mode has something to show locally.
-- With three riders sharing, the stats panel shows the rider count, and the two incident areas
-- below each have 3 shared reports from 2 riders, older than 24 hours, so they pass the
-- public_incident_cells thresholds. Still LOCAL/DEV ONLY.
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'seed2@example.test',
   '2026-10-10T00:00:00Z', '2026-10-10T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'seed3@example.test',
   '2026-10-10T00:00:00Z', '2026-10-10T00:00:00Z')
on conflict do nothing;

-- Short shared rides along Lady Bird Lake (rider 2) and Congress Ave (rider 3).
-- Active time stays within each ride's start-to-end span, as the upload limits require.
insert into rides (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route, app_version, share_publicly)
values
  ('10000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000002',
   '2026-10-20T14:00:00Z', '2026-10-20T14:08:00Z', 1500, 450, 3.333,
   '{"type":"LineString","coordinates":[[-97.7465,30.2668],[-97.743,30.2672],[-97.7395,30.2679],[-97.736,30.2688]]}'::jsonb,
   '0.1.0', true),
  ('10000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000003',
   '2026-10-18T15:00:00Z', '2026-10-18T15:07:00Z', 1500, 400, 3.75,
   '{"type":"LineString","coordinates":[[-97.7429,30.2705],[-97.7428,30.2738],[-97.7427,30.2771],[-97.7426,30.2804]]}'::jsonb,
   '0.1.0', true)
on conflict do nothing;

-- Shared incidents. Area A rounds to (30.267, -97.743): riders 1 and 2.
-- Area B rounds to (30.277, -97.743): riders 1 and 3. Each near miss sits inside its ride's window.
insert into near_misses (id, ride_id, user_id, occurred_at, latitude, longitude, kind, confidence, position_hint, source, share_publicly)
values
  ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000002', '2026-10-20T14:03:00Z', 30.2671, -97.7431, 'vehicle', 0.81, 'left',   'detected',       true),
  ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000002', '2026-10-20T14:04:00Z', 30.2669, -97.7428, 'vehicle', null, null,     'rider_reported', true),
  ('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000001', '2026-10-22T22:34:30Z', 30.2673, -97.7432, 'truck',   0.77, 'right',  'detected',       true),
  ('20000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000003', '2026-10-18T15:03:00Z', 30.2771, -97.7427, 'vehicle', 0.88, 'center', 'detected',       true),
  ('20000000-0000-4000-8000-000000000009', '10000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000003', '2026-10-18T15:04:00Z', 30.2768, -97.7426, 'car',     null, null,     'rider_reported', true),
  ('20000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000001', '2026-10-19T13:17:00Z', 30.2772, -97.7428, 'car',     0.69, 'left',   'detected',       true)
on conflict do nothing;
