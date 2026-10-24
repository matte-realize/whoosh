-- near_misses: per-ride hazard events (future feature).
-- NOT USED BY THE MVP APP YET. The table exists so the contract and RLS are settled before the
-- detection feature ships. Source of truth: .kiro/team/supabase-contract.md (draft 0.1).
--
-- Notes:
--   * latitude/longitude are the nearest accepted route point, not a raw GPS fix.
--   * kind comes from HazardDetection.kind (for example 'vehicle').
--   * No camera video or frames are ever stored here.
--   * Depends on 20261024120000_rides.sql.

create table near_misses (
  id            uuid primary key default gen_random_uuid(),
  ride_id       uuid not null references rides (id) on delete cascade,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  occurred_at   timestamptz not null,
  latitude      float8 not null,
  longitude     float8 not null,
  kind          text not null,
  confidence    float8 not null check (confidence between 0 and 1),
  position_hint text check (position_hint in ('left', 'center', 'right'))
);

-- Data API grants (see the note in 20261024120000_rides.sql). `anon` gets nothing here.
grant select, insert, update, delete on public.near_misses to authenticated;
grant select, insert, update, delete on public.near_misses to service_role;

-- Row level security: users can only touch their own rows.
alter table near_misses enable row level security;

create policy "own near_misses: select" on near_misses
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Insert and update also require that the referenced ride belongs to the same user. Without
-- this, a user who knew another user's ride id could attach near misses to that ride.
-- The subquery on rides runs under the caller's own RLS, so it can only see the caller's rides.
create policy "own near_misses: insert" on near_misses
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.rides r
      where r.id = near_misses.ride_id and r.user_id = (select auth.uid())
    )
  );

create policy "own near_misses: update" on near_misses
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.rides r
      where r.id = near_misses.ride_id and r.user_id = (select auth.uid())
    )
  );

create policy "own near_misses: delete" on near_misses
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Fetch all near misses for a ride; also speeds up the cascade delete from rides.
create index near_misses_ride_id_idx on near_misses (ride_id);
