-- Input limits on uploaded data, and an aggregate-only stats view for the website.
-- New migration; earlier ones are applied and are not edited.
--
-- Why limits: anyone can get an anonymous account, and every shared route is served to every
-- website visitor through public_rides. Without limits one bad or malicious upload could store an
-- arbitrarily large route, impossible coordinates, or nonsense metrics.

-- ---------------------------------------------------------------------------
-- 1. Route validation
-- ---------------------------------------------------------------------------

-- A valid route is a GeoJSON LineString with 2 to 10,000 points. Each point is [lon, lat] or
-- [lon, lat, altitude], all numbers, with lon in -180..180 and lat in -90..90.
-- 10,000 points covers a long ride at one point every few seconds. The app should simplify
-- routes before upload anyway (privacy trim first, then thin points), which keeps the website fast.
--
-- plpgsql with nested IFs so every check runs in a guaranteed order (jsonb_array_length raises
-- an error on a non-array, so the type check must come first).
create function public.is_valid_route(route jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  point jsonb;
  point_count integer;
  axis integer;
begin
  if route is null or jsonb_typeof(route) <> 'object' then
    return false;
  end if;
  if (route ->> 'type') is distinct from 'LineString' then
    return false;
  end if;
  if jsonb_typeof(route -> 'coordinates') is distinct from 'array' then
    return false;
  end if;

  point_count := jsonb_array_length(route -> 'coordinates');
  if point_count < 2 or point_count > 10000 then
    return false;
  end if;

  for point in select value from jsonb_array_elements(route -> 'coordinates') loop
    if jsonb_typeof(point) <> 'array' then
      return false;
    end if;
    if jsonb_array_length(point) < 2 or jsonb_array_length(point) > 3 then
      return false;
    end if;
    for axis in 0 .. jsonb_array_length(point) - 1 loop
      if jsonb_typeof(point -> axis) <> 'number' then
        return false;
      end if;
    end loop;
    if (point ->> 0)::float8 not between -180 and 180 then
      return false;
    end if;
    if (point ->> 1)::float8 not between -90 and 90 then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

-- The function reads no data, so calling it directly (it is reachable as an RPC) reveals nothing.
-- Execute is limited to the roles that insert rides; check constraints run with the inserting
-- role's privileges.
revoke all on function public.is_valid_route(jsonb) from public, anon;
grant execute on function public.is_valid_route(jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. rides limits
-- ---------------------------------------------------------------------------

alter table public.rides
  add constraint rides_route_valid check (public.is_valid_route(route)),
  -- 1,000 km, 48 hours, and 40 m/s (144 km/h, beyond any downhill) are far above any real ride.
  add constraint rides_distance_max check (distance_m <= 1000000),
  add constraint rides_active_duration_max check (active_duration_s <= 172800),
  add constraint rides_avg_speed_max check (avg_speed_mps <= 40),
  add constraint rides_elapsed_max check (ended_at <= started_at + interval '48 hours'),
  -- Active time excludes pauses, so it cannot exceed the wall-clock span (1 s of slack for rounding).
  add constraint rides_active_within_elapsed
    check (active_duration_s <= extract(epoch from (ended_at - started_at)) + 1),
  add constraint rides_app_version_length check (app_version is null or char_length(app_version) <= 32);

-- ---------------------------------------------------------------------------
-- 3. near_misses limits
-- ---------------------------------------------------------------------------

alter table public.near_misses
  add constraint near_misses_latitude_range check (latitude between -90 and 90),
  add constraint near_misses_longitude_range check (longitude between -180 and 180),
  add constraint near_misses_kind_length check (char_length(kind) between 1 and 32);

-- ---------------------------------------------------------------------------
-- 4. public_stats: one row of totals for the website's big-screen panel
-- ---------------------------------------------------------------------------
--
-- Aggregates only. Totals are over shared rides, which are public individually already.
-- The rider count is shown only when at least 3 riders have shared rides: with fewer, the count
-- would tell visitors that the shared rides all come from one or two people.
-- Incident figures come from public_incident_cells, so they include only cells that already
-- passed that view's thresholds.
--
-- Same deliberate choice as the other public views: owner rights, security_barrier, and
-- select for anon only.

create view public.public_stats
with (security_barrier = true) as
select
  count(*)                                           as shared_rides,
  coalesce(sum(r.distance_m), 0)::float8              as total_distance_m,
  coalesce(sum(r.active_duration_s), 0)::float8       as total_active_duration_s,
  case when count(distinct r.user_id) >= 3
       then count(distinct r.user_id) end            as riders,
  (select coalesce(sum(c.incident_count), 0)::bigint
     from public.public_incident_cells c)             as mapped_incidents,
  (select count(*) from public.public_incident_cells) as incident_cells
from public.rides r
where r.share_publicly;

revoke all on public.public_stats from public, anon, authenticated;
grant select on public.public_stats to anon;
