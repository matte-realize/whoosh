-- rides: finished-ride summaries synced from the Whoosh iOS app (opt-in sync only).
-- Source of truth: .kiro/team/supabase-contract.md (draft 0.1) plus the share_publicly decision.
--
-- Notes:
--   * route is a GeoJSON LineString ([longitude, latitude] order) stored as jsonb.
--     It is privacy-trimmed by the app before upload (160 m from each end by default).
--     The database does not trim; it only stores what the app sends.
--   * All stored values are SI units (meters, seconds, meters/second).
--     Timestamps are timestamptz (UTC).
--   * id is generated on the device so that upserts are idempotent. There is no server default.
--   * Anonymous sign-in users have the "authenticated" role, so the policies below apply to them.

create table rides (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  started_at        timestamptz not null,
  ended_at          timestamptz not null,
  distance_m        float8 not null check (distance_m >= 0),
  active_duration_s float8 not null check (active_duration_s >= 0),
  avg_speed_mps     float8 not null check (avg_speed_mps >= 0),
  route             jsonb not null,
  app_version       text,
  created_at        timestamptz not null default now(),
  share_publicly    boolean not null default false,

  constraint rides_ended_after_started check (ended_at >= started_at),
  constraint rides_route_is_linestring check (route ->> 'type' = 'LineString')
);

-- Data API grants. Supabase no longer grants access to new tables in `public` automatically
-- (new projects since 2026-05-30, all projects from 2026-10-30), so the roles that need the table
-- get an explicit grant here. `anon` is deliberately NOT granted: the website reads the
-- public_rides view instead (see 20261024120200_public_rides_view.sql). Grants decide whether a
-- role can touch the table at all; the RLS policies below decide which rows.
-- service_role is for Role C's admin/seed scripts and bypasses RLS; its key never leaves C.
grant select, insert, update, delete on public.rides to authenticated;
grant select, insert, update, delete on public.rides to service_role;

-- Row level security: users can only touch their own rows.
-- (select auth.uid()) lets Postgres evaluate the function once per statement instead of per row.
alter table rides enable row level security;

create policy "own rides: select" on rides
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "own rides: insert" on rides
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "own rides: update" on rides
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "own rides: delete" on rides
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Ride history queries: a user's rides, newest first.
create index rides_user_id_started_at_idx on rides (user_id, started_at desc);
