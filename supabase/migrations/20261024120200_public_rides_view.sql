-- public_rides: the ONLY thing the public website (role `anon`) may read.
-- Source of truth: .kiro/team/supabase-contract.md, "Website access" (option 2, public demo view).
-- Backend task B3. Depends on 20261024120000_rides.sql and 20261024120100_near_misses.sql.
--
-- PURPOSE
--   Let the web dashboard show rides on a big screen without signing in, and without ever
--   touching the raw tables. The browser uses the public key (role `anon`) and can read this
--   view and nothing else.
--
-- COLUMNS EXPOSED, AND WHY
--   id                 identifies the ride in the UI (a random uuid generated on the device).
--   started_at         lets the site order and label rides.
--   distance_m         summary stat (meters).
--   active_duration_s  summary stat (seconds, excludes paused time).
--   avg_speed_mps      summary stat (meters/second).
--   route              GeoJSON LineString to draw on the map. The app has already trimmed
--                      160 m (default) from each end before upload, so the rider's home or work
--                      is not in the stored route. The database does not trim it again.
--
-- COLUMNS DELIBERATELY NOT EXPOSED
--   user_id         would let anyone link rides to one anonymous account.
--   ended_at        started_at + active_duration_s is enough for display; fewer fields, less leak.
--   app_version     debugging only.
--   created_at      upload time; not needed and can hint at when the rider got home.
--   share_publicly  every row in the view has it true, so it carries no information.
--
-- WHEN A ROW APPEARS
--   Only for rides where share_publicly = true. The app sets that column from a separate,
--   explicit opt-in toggle (default false). Un-sharing or deleting a ride in the app removes
--   it from the view immediately.
--
-- DELIBERATE, REVIEWED CHOICE: the view runs with its OWNER's rights (the Postgres default;
-- security_invoker is NOT set).
--   The view is owned by the migration role (`postgres`), which is the owner of `rides` and is
--   not subject to its RLS policies, so the view can read the shared rows even though `anon` has
--   no policy, and (see the revokes below) no privilege, on public.rides. The WHERE clause is the
--   access rule, and the column list is the privacy filter. Any change to either needs review.
--   `security_barrier` is set so that a caller's own WHERE conditions cannot be evaluated
--   against non-shared rows before the view's share_publicly filter runs (prevents leaking
--   unshared rows through error messages or leaky functions).
--
--   HEADS-UP FOR ROLE C: Supabase's security advisor may flag this view with the
--   `security_definer_view` lint (a view that runs with its creator's permissions). That is
--   expected here. The alternative, if C prefers to satisfy the lint, is:
--     1. create the view with (security_invoker = true);
--     2. give `anon` COLUMN-level select on only the six columns above plus share_publicly:
--          grant select (id, started_at, distance_m, active_duration_s, avg_speed_mps, route,
--                        share_publicly) on public.rides to anon;
--     3. add an anon select policy on rides:
--          create policy "public rides: select shared" on public.rides
--            for select to anon using (share_publicly = true);
--   That puts a direct (column-limited) grant and a policy on the raw table, so a later mistake
--   in either one exposes data without the view. The owner-rights view keeps the exposure in a
--   single reviewed object, which is why it is used here.

create view public.public_rides
with (security_barrier = true) as
select
  id,
  started_at,
  distance_m,
  active_duration_s,
  avg_speed_mps,
  route
from public.rides
where share_publicly = true;

-- Defense in depth: `anon` has no direct access to any table. On older projects Supabase's default
-- privileges granted `anon` broad rights on new public tables, so RLS alone would be the only
-- barrier there; newer projects grant nothing by default. Either way, revoking makes a missing or
-- wrong policy fail closed with "permission denied" (42501).
revoke all on public.rides from anon;
revoke all on public.near_misses from anon;

-- The view: nothing for anyone by default (this also removes the default grants Supabase adds to
-- new objects in `public`), then read-only for `anon`. `authenticated` is intentionally not
-- granted: the website reads as `anon`, and the app talks to the `rides` table directly.
revoke all on public.public_rides from public, anon, authenticated;
grant select on public.public_rides to anon;
