-- RLS isolation tests for public.rides and public.near_misses (backend task B2), plus the
-- public.public_rides view and the anon revokes from backend task B3.
--
-- HOW TO RUN
--   supabase test db
--   (needs the local stack: `supabase start`; pgTAP is bundled with the local database.)
--
-- WHAT IT PROVES
--   Two users (A and B) cannot see, change, or delete each other's rows, cannot insert rows
--   owned by someone else, and the `anon` role (no session) has no direct table access at all
--   (permission denied on rides and near_misses). `anon` can read only public.public_rides, which
--   returns only rides with share_publicly = true, has no user_id column, and is read-only.
--   Signed-in users (role `authenticated`) have no select on the view.
--
-- SEED DATA
--   The file deletes all rides at the start (inside its transaction) so it does not depend on
--   what seed.sql loaded. The rollback at the end puts the seeded rows back.
--
-- ASSERTION LABELS
--   The "-- N" comments are stable labels, not run order. Some run out of numeric order (for
--   example 5 and 7 run after 8). pgTAP numbers the output by run order.
--
-- HOW TO CHECK THE TEST HAS TEETH
--   Temporarily drop one policy in a scratch database, for example
--     drop policy "own rides: select" on public.rides;
--   and re-run `supabase test db`. The matching assertion(s) must fail. Never do this on a
--   shared or remote database. The whole file runs in one transaction and rolls back, so the
--   fixtures below leave no data behind.
--
-- HOW SESSIONS ARE SIMULATED
--   Fixtures are inserted as the superuser. A session is then simulated with
--     reset role;
--     select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
--     set local role authenticated;
--   auth.uid() reads the `sub` claim from request.jwt.claims.
--
-- NEAR-MISS OWNERSHIP: the near_misses insert/update policies also require that ride_id belongs
--   to the same user (an exists() check on rides). Assertion 27 covers the insert case and
--   assertion 29 covers re-pointing an existing near miss at someone else's ride.
--
-- SHARING FLOW: assertions 30 to 34 check that flipping share_publicly adds or removes a ride in
--   public_rides for anon, and that another user cannot flip it.
--
-- NOTE: the anon assertions assume migration 20261024120200_public_rides_view.sql has run. It
--   revokes ALL table privileges on rides and near_misses from `anon`, so any direct anon access
--   raises "permission denied" (SQLSTATE 42501) before RLS is even consulted. If that revoke is
--   removed, the anon select assertions (10 and 20) will fail because they would return 0 rows
--   (RLS) instead of raising an error, and this file will need adjusting.

begin;

select plan(34);

-- `supabase db reset` loads supabase/seed.sql, which contains a shared ride. Counts below assume
-- only this file's fixtures exist, so clear the seeded rows (and their near misses, by cascade)
-- first. This runs as the superuser inside the transaction, and the final rollback restores them.
delete from public.rides;

-- ---------------------------------------------------------------------------
-- Fixtures (run as the superuser, before any role switch)
-- ---------------------------------------------------------------------------

insert into auth.users (id, aud, role, email)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'user-a@example.test'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'authenticated', 'authenticated', 'user-b@example.test');

-- A second ride owned by user A, opted in to public sharing. It is the only row public_rides
-- should show. (User A's other ride, inserted below as A, keeps share_publicly = false.)
insert into public.rides
  (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route,
   share_publicly)
values
  ('66666666-6666-4666-8666-666666666666',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   '2026-10-24 11:00:00+00', '2026-10-24 11:20:00+00',
   2000, 1200, 1.6667,
   '{"type":"LineString","coordinates":[[-122.4300,37.7800],[-122.4250,37.7830]]}'::jsonb,
   true);

-- ---------------------------------------------------------------------------
-- User A: insert and read back own ride
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 1
select lives_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('11111111-1111-4111-8111-111111111111',
       '2026-10-24 12:00:00+00', '2026-10-24 12:10:00+00',
       1000, 600, 1.6667,
       '{"type":"LineString","coordinates":[[-122.4194,37.7749],[-122.4180,37.7760]]}'::jsonb)$$,
  'user A can insert their own ride (user_id defaults to auth.uid())'
);

-- 2
select is(
  (select count(*) from public.rides where id = '11111111-1111-4111-8111-111111111111'),
  1::bigint,
  'user A can read back their own ride (1 row)'
);

-- ---------------------------------------------------------------------------
-- User B: cannot see, update, or delete A's ride
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;

-- 3 (A owns two rides, one private and one shared; B must see neither)
select is(
  (select count(*) from public.rides),
  0::bigint,
  'user B sees 0 rows in rides'
);

-- 4 (RLS filters the row silently: no error, 0 rows affected; the effect is checked in 5)
select lives_ok(
  $$update public.rides set distance_m = 999999
      where id = '11111111-1111-4111-8111-111111111111'$$,
  'user B update of A''s ride runs without error (matches 0 rows)'
);

-- 6 (same idea for delete; the effect is checked in 7)
select lives_ok(
  $$delete from public.rides where id = '11111111-1111-4111-8111-111111111111'$$,
  'user B delete of A''s ride runs without error (matches 0 rows)'
);

-- 8
select throws_ok(
  $$insert into public.rides
      (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('22222222-2222-4222-8222-222222222222',
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       '2026-10-24 13:00:00+00', '2026-10-24 13:05:00+00',
       500, 300, 1.6667,
       '{"type":"LineString","coordinates":[[-122.4194,37.7749],[-122.4180,37.7760]]}'::jsonb)$$,
  '42501',
  null,
  'user B cannot insert a ride with user_id = A (RLS violation)'
);

-- ---------------------------------------------------------------------------
-- Back to user A: B's update and delete must have had no effect
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 5
select is(
  (select distance_m from public.rides where id = '11111111-1111-4111-8111-111111111111'),
  1000::float8,
  'user B''s update affected 0 rows: A''s distance_m is unchanged'
);

-- 7
select is(
  (select count(*) from public.rides where id = '11111111-1111-4111-8111-111111111111'),
  1::bigint,
  'user B''s delete affected 0 rows: A still sees the ride'
);

-- 9
select throws_ok(
  $$update public.rides set user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      where id = '11111111-1111-4111-8111-111111111111'$$,
  '42501',
  null,
  'user A cannot reassign their ride to user B (with check violation)'
);

-- ---------------------------------------------------------------------------
-- anon role, no session
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 10 (anon has no table privileges after the B3 migration: permission denied, not 0 rows)
select throws_ok(
  $$select count(*) from public.rides$$,
  '42501',
  null,
  'anon cannot select from rides (permission denied)'
);

-- 11
select throws_ok(
  $$insert into public.rides
      (id, user_id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('33333333-3333-4333-8333-333333333333',
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       '2026-10-24 14:00:00+00', '2026-10-24 14:05:00+00',
       500, 300, 1.6667,
       '{"type":"LineString","coordinates":[[-122.4194,37.7749],[-122.4180,37.7760]]}'::jsonb)$$,
  '42501',
  null,
  'anon cannot insert a ride (permission denied)'
);

-- ---------------------------------------------------------------------------
-- public.public_rides: what the website (anon) may read
-- ---------------------------------------------------------------------------

-- Still the anon role from the block above.

-- 18 (A has two rides; only the shared one may appear)
select is(
  (select count(*) from public.public_rides),
  1::bigint,
  'anon sees exactly 1 row in public_rides (only the shared ride)'
);

-- 19
select is(
  (select id from public.public_rides),
  '66666666-6666-4666-8666-666666666666'::uuid,
  'the one public_rides row is the shared ride, not the private one'
);

-- 20 (no direct access to near_misses either)
select throws_ok(
  $$select count(*) from public.near_misses$$,
  '42501',
  null,
  'anon cannot select from near_misses (permission denied)'
);

-- 21 (the view is read-only for anon; privilege is checked on the view before anything runs)
select throws_ok(
  $$insert into public.public_rides
      (id, started_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('77777777-7777-4777-8777-777777777777',
       '2026-10-24 15:00:00+00', 500, 300, 1.6667,
       '{"type":"LineString","coordinates":[[-122.4194,37.7749],[-122.4180,37.7760]]}'::jsonb)$$,
  '42501',
  null,
  'anon cannot insert through public_rides (permission denied)'
);

-- 22
select throws_ok(
  $$update public.public_rides set distance_m = 999999$$,
  '42501',
  null,
  'anon cannot update through public_rides (permission denied)'
);

-- 23
select throws_ok(
  $$delete from public.public_rides$$,
  '42501',
  null,
  'anon cannot delete through public_rides (permission denied)'
);

-- Catalog checks run as the superuser (not as anon).
reset role;

-- 24 (exact column list: this also proves user_id, ended_at, app_version, created_at and
--     share_publicly are absent)
select columns_are(
  'public',
  'public_rides',
  array['id', 'started_at', 'distance_m', 'active_duration_s', 'avg_speed_mps', 'route'],
  'public_rides exposes exactly id, started_at, distance_m, active_duration_s, avg_speed_mps, route'
);

-- 25 (explicit check for the most sensitive column, for a clearer failure message)
select hasnt_column(
  'public',
  'public_rides',
  'user_id',
  'public_rides has no user_id column'
);

-- 26 (signed-in users get no select on the view: the website must read as anon)
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select count(*) from public.public_rides$$,
  '42501',
  null,
  'authenticated user B cannot select from public_rides (granted to anon only)'
);

-- ---------------------------------------------------------------------------
-- near_misses: same select/insert isolation
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 12
select lives_ok(
  $$insert into public.near_misses
      (id, ride_id, occurred_at, latitude, longitude, kind, confidence, position_hint)
    values
      ('44444444-4444-4444-8444-444444444444',
       '11111111-1111-4111-8111-111111111111',
       '2026-10-24 12:05:00+00', 37.7755, -122.4187, 'vehicle', 0.9, 'left')$$,
  'user A can insert a near miss for their own ride'
);

-- 13
select is(
  (select count(*) from public.near_misses),
  1::bigint,
  'user A can read back their own near miss (1 row)'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;

-- 14
select is(
  (select count(*) from public.near_misses),
  0::bigint,
  'user B sees 0 rows in near_misses'
);

-- 15
select throws_ok(
  $$insert into public.near_misses
      (id, ride_id, user_id, occurred_at, latitude, longitude, kind, confidence)
    values
      ('55555555-5555-4555-8555-555555555555',
       '11111111-1111-4111-8111-111111111111',
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       '2026-10-24 12:06:00+00', 37.7756, -122.4186, 'vehicle', 0.8)$$,
  '42501',
  null,
  'user B cannot insert a near miss with user_id = A (RLS violation)'
);

-- 27 (B's own user_id, but A's ride: the ride-ownership check must reject it)
select throws_ok(
  $$insert into public.near_misses
      (id, ride_id, user_id, occurred_at, latitude, longitude, kind, confidence)
    values
      ('88888888-8888-4888-8888-888888888888',
       '11111111-1111-4111-8111-111111111111',
       'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       '2026-10-24 12:07:00+00', 37.7757, -122.4185, 'vehicle', 0.7)$$,
  '42501',
  null,
  'user B cannot attach a near miss to A''s ride, even with user_id = B'
);

-- 28 (B gets a ride of their own, private by default; used as the re-point target below)
select lives_ok(
  $$insert into public.rides
      (id, started_at, ended_at, distance_m, active_duration_s, avg_speed_mps, route)
    values
      ('99999999-9999-4999-8999-999999999999',
       '2026-10-24 16:00:00+00', '2026-10-24 16:10:00+00',
       800, 600, 1.3333,
       '{"type":"LineString","coordinates":[[-122.4100,37.7700],[-122.4090,37.7710]]}'::jsonb)$$,
  'user B can insert their own ride'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 29 (update path: A's own near miss cannot be re-pointed at B's ride; with check fails)
select throws_ok(
  $$update public.near_misses
      set ride_id = '99999999-9999-4999-8999-999999999999'
      where id = '44444444-4444-4444-8444-444444444444'$$,
  '42501',
  null,
  'user A cannot re-point their near miss at another user''s ride'
);

-- ---------------------------------------------------------------------------
-- User A deletes their own ride (last, because it cascades to near_misses)
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 16
select lives_ok(
  $$delete from public.rides where id = '11111111-1111-4111-8111-111111111111'$$,
  'user A can delete their own ride'
);

-- 17 (A's shared ride is still there, so exactly 1 row remains: the delete hit only the private ride)
select is(
  (select count(*) from public.rides),
  1::bigint,
  'after deleting the private ride, user A sees only the shared ride (1 row in rides)'
);

-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Sharing flow: share_publicly controls whether a ride appears in public_rides
-- (ride 6666 is A's shared ride and the only one in the view so far; B's ride is private)
-- ---------------------------------------------------------------------------

-- 30 (A turns sharing off for their own ride)
select lives_ok(
  $$update public.rides set share_publicly = false
      where id = '66666666-6666-4666-8666-666666666666'$$,
  'user A can stop sharing their own ride'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 31
select is(
  (select count(*) from public.public_rides),
  0::bigint,
  'after A unshares, anon sees 0 rows in public_rides'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

-- 32
select lives_ok(
  $$update public.rides set share_publicly = true
      where id = '66666666-6666-4666-8666-666666666666'$$,
  'user A can share their own ride again'
);

reset role;
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
set local role authenticated;

-- 33 (B tries to unshare A's ride: RLS hides the row, so no error and 0 rows change)
select lives_ok(
  $$update public.rides set share_publicly = false
      where id = '66666666-6666-4666-8666-666666666666'$$,
  'user B update of A''s share flag runs without error (matches 0 rows)'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

-- 34 (still exactly A's shared ride: B's change had no effect, and B's private ride is not shown)
select is(
  (select count(*) from public.public_rides
     where id = '66666666-6666-4666-8666-666666666666'),
  1::bigint,
  'anon still sees A''s shared ride after B''s attempted unshare'
);

-- ---------------------------------------------------------------------------

reset role;
select * from finish();

rollback;
