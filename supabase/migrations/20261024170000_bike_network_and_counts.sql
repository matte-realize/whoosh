-- Two more real city layers next to the crash records: the bike network and bike counts.
--
-- WHY
--   Crash counts alone can't say whether a street is dangerous or just busy, or whether a new
--   lane changed anything. The city also publishes what kind of bike lane is on each block (and
--   when it was installed) and how many bikes and motor vehicles pass its counters. Together they
--   give each crash its context and each block a measured volume.
--
-- WHAT
--   bike_facility_types         the city's facility codes (BL, SBL, ...), with a simple protection class.
--   bike_facilities             one row per published lane segment, as a GeoJSON LineString.
--   bike_count_locations        one row per city counter.
--   bike_count_days             one row per counter per local day: bikes and motor vehicles.
--   public_bike_facilities      anon: segments with type, protection, install year, attribution.
--   public_bike_count_locations anon: each counter with its latest year's daily averages.
--   public_bike_count_years     anon: each counter's daily averages per year, with days counted.
--   public_crash_facility_context
--                               anon: each city bike crash with the nearest lane segment and
--                               whether that lane was already there at the time.
--
-- HONESTY
--   Counters run a few days a year, so yearly figures are averages of 2 to 8 days. The network
--   inventory has only the current lane and its install year, not what was there before.
--   Crashes near a lane are matched by distance (at most 25 m), not by the police report.
--
-- LOADING
--   supabase/data/boston-bike-network/import.py and supabase/data/boston-bike-counts/import.py
--   write upserts. Their first snapshots are applied by migrations 20261024170100 and 170200.

-- ---------------------------------------------------------------------------
-- 1. Facility types (reference data, owned by this migration)
-- ---------------------------------------------------------------------------

create table public.bike_facility_types (
  code       text primary key,
  label      text not null,
  -- separated: a physical barrier on both sides; partly_separated: on one side;
  -- painted: paint only; shared: riders share the lane with traffic; path: off-street.
  protection text not null,

  constraint bike_facility_types_code_format check (code ~ '^[A-Z][A-Z-]{1,15}$'),
  constraint bike_facility_types_protection_check
    check (protection in ('separated', 'partly_separated', 'painted', 'shared', 'path'))
);

-- Labels are the coded-value domain of the city's ArcGIS layer Boston_Bicycle_Network_2024.
-- BL-PEAKBUS appears in the data without a label in the domain.
insert into public.bike_facility_types (code, label, protection) values
  ('BL',         'Bike lane',                                                   'painted'),
  ('BFBL',       'Buffered bike lane',                                          'painted'),
  ('BLSL',       'Bike lane on one side, shared lane on the other side',        'painted'),
  ('CFBL',       'Contraflow bike lane',                                        'painted'),
  ('BL-PEAKBUS', 'Bike lane, bus lane at peak hours',                           'painted'),
  ('SBL',        'Separated bike lane',                                         'separated'),
  ('CFSBL',      'Contraflow separated bike lane',                              'separated'),
  ('SBLBL',      'Separated bike lane one side, bike lane on the other side',   'partly_separated'),
  ('SBLSL',      'Separated bike lane one side, shared lane on the other side', 'partly_separated'),
  ('SLM',        'Shared lane markings or shared bus lane',                     'shared'),
  ('SLMTC',      'Shared lane markings on a traffic calmed street',             'shared'),
  ('CFBS',       'Contraflow bike street',                                      'shared'),
  ('PED',        'Pedestrianized street',                                       'path'),
  ('SUP',        'Shared use path',                                             'path'),
  ('SUPN',       'Natural surface shared use path',                             'path'),
  ('SUPM',       'Minor shared use path',                                       'path'),
  ('WALK',       'Walkway',                                                     'path');

-- ---------------------------------------------------------------------------
-- 2. Bike facilities (lane segments)
-- ---------------------------------------------------------------------------

create table public.bike_facilities (
  id               bigint generated always as identity primary key,
  source           text not null references public.data_sources (key) on update cascade,
  source_record_id text not null,
  street           text,
  facility_code    text not null references public.bike_facility_types (code) on update cascade,
  install_year     smallint,
  -- GeoJSON LineString, [lon, lat]. Same rules as rides.route.
  route            jsonb not null,
  imported_at      timestamptz not null default now(),

  constraint bike_facilities_source_record_key unique (source, source_record_id),
  constraint bike_facilities_route_valid check (public.is_valid_route(route)),
  constraint bike_facilities_install_year_range check (install_year between 1970 and 2100),
  constraint bike_facilities_street_length check (char_length(street) <= 120)
);

create index bike_facilities_facility_code_idx on public.bike_facilities (facility_code);

-- ---------------------------------------------------------------------------
-- 3. Bike counts
-- ---------------------------------------------------------------------------

create table public.bike_count_locations (
  source      text not null references public.data_sources (key) on update cascade,
  -- The source's id for the counting location (Boston: count_id).
  location_id text not null,
  name        text not null,
  latitude    float8 not null,
  longitude   float8 not null,
  updated_at  timestamptz not null default now(),

  primary key (source, location_id),
  constraint bike_count_locations_name_length check (char_length(name) between 1 and 120),
  constraint bike_count_locations_latitude_range check (latitude between -90 and 90),
  constraint bike_count_locations_longitude_range check (longitude between -180 and 180)
);

create table public.bike_count_days (
  source         text not null,
  location_id    text not null,
  -- The local calendar day counted.
  count_date     date not null,
  -- Hours with data that day. Only full days (24) feed the public averages.
  hours_counted  smallint not null,
  -- Both directions summed.
  bikes          integer not null,
  motor_vehicles integer,
  imported_at    timestamptz not null default now(),

  primary key (source, location_id, count_date),
  foreign key (source, location_id) references public.bike_count_locations (source, location_id)
    on update cascade on delete cascade,
  constraint bike_count_days_hours_range check (hours_counted between 1 and 24),
  -- 100,000 a day is far above any single street's traffic; anything larger is a bad record.
  constraint bike_count_days_bikes_range check (bikes between 0 and 100000),
  constraint bike_count_days_motor_vehicles_range check (motor_vehicles between 0 and 500000)
);

-- ---------------------------------------------------------------------------
-- 4. Distance helper
-- ---------------------------------------------------------------------------
--
-- Meters from a point to a segment, on a local flat projection around the point. Accurate to
-- well under a meter at street scale, which is all it is used for. No PostGIS needed.

create function public.segment_distance_m(
  p_lat float8, p_lon float8, a_lat float8, a_lon float8, b_lat float8, b_lon float8
)
returns float8
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select sqrt(power(ax + t * dx, 2) + power(ay + t * dy, 2))
  from (
    select ax, ay, dx, dy,
           -- Projection of the point onto the segment, clamped to its ends. A zero-length
           -- segment gives null here, and greatest/least ignore nulls, so t becomes 1 (= its end).
           greatest(0, least(1, -(ax * dx + ay * dy) / nullif(dx * dx + dy * dy, 0))) as t
    from (
      select (a_lon - p_lon) * kx as ax, (a_lat - p_lat) * ky as ay,
             (b_lon - a_lon) * kx as dx, (b_lat - a_lat) * ky as dy
      from (select 111320 * cos(radians(p_lat)) as kx, 110574.0::float8 as ky) k
    ) v
  ) w;
$$;

-- Postgres checks EXECUTE on functions inside a view against the caller, not the view owner, so
-- anon (which reads public_crash_facility_context) needs it. The function is pure arithmetic and
-- reads no tables, so this exposes nothing.
revoke all on function public.segment_distance_m(float8, float8, float8, float8, float8, float8)
  from public, anon, authenticated;
grant execute on function public.segment_distance_m(float8, float8, float8, float8, float8, float8)
  to anon, service_role;

-- ---------------------------------------------------------------------------
-- 5. Grants and RLS on the tables
-- ---------------------------------------------------------------------------

revoke all on table public.bike_facility_types, public.bike_facilities,
  public.bike_count_locations, public.bike_count_days from public, anon, authenticated;
grant all on table public.bike_facility_types, public.bike_facilities,
  public.bike_count_locations, public.bike_count_days to service_role;

alter table public.bike_facility_types enable row level security;
alter table public.bike_facilities enable row level security;
alter table public.bike_count_locations enable row level security;
alter table public.bike_count_days enable row level security;

-- ---------------------------------------------------------------------------
-- 6. Views for the website (anon)
-- ---------------------------------------------------------------------------

create view public.public_bike_facilities
with (security_barrier = true) as
select
  f.source,
  f.source_record_id,
  f.street,
  f.facility_code,
  t.label      as facility_label,
  t.protection,
  f.install_year,
  f.route,
  s.name       as source_name,
  s.license    as source_license,
  s.url        as source_url
from public.bike_facilities f
join public.bike_facility_types t on t.code = f.facility_code
join public.data_sources s on s.key = f.source;

-- Per counter per year, full days only. avg_* are rounded to whole vehicles.
create view public.public_bike_count_years
with (security_barrier = true) as
select
  d.source,
  d.location_id,
  extract(year from d.count_date)::integer          as year,
  count(*)                                          as days_counted,
  round(avg(d.bikes))::integer                      as avg_daily_bikes,
  min(d.bikes)                                      as min_daily_bikes,
  max(d.bikes)                                      as max_daily_bikes,
  round(avg(d.motor_vehicles))::integer             as avg_daily_motor_vehicles
from public.bike_count_days d
where d.hours_counted = 24
group by d.source, d.location_id, extract(year from d.count_date);

-- Each counter with its overall span and its latest counted year.
create view public.public_bike_count_locations
with (security_barrier = true) as
with latest as (
  select distinct on (y.source, y.location_id) y.*
  from public.public_bike_count_years y
  order by y.source, y.location_id, y.year desc
),
span as (
  select source, location_id,
         sum(days_counted)::integer as days_counted,
         min(year) as first_year,
         max(year) as last_year
  from public.public_bike_count_years
  group by source, location_id
)
select
  l.source,
  l.location_id,
  l.name,
  l.latitude,
  l.longitude,
  sp.days_counted,
  sp.first_year,
  sp.last_year,
  la.days_counted              as latest_year_days,
  la.avg_daily_bikes           as latest_avg_daily_bikes,
  la.avg_daily_motor_vehicles  as latest_avg_daily_motor_vehicles,
  -- Bikes as a share of all counted vehicles, 0 to 1, 3 decimals.
  round(la.avg_daily_bikes::numeric
        / nullif(la.avg_daily_bikes + coalesce(la.avg_daily_motor_vehicles, 0), 0), 3)::float8
                               as latest_bike_share,
  s.name                       as source_name,
  s.license                    as source_license,
  s.url                        as source_url
from public.bike_count_locations l
join span sp on sp.source = l.source and sp.location_id = l.location_id
join latest la on la.source = l.source and la.location_id = l.location_id
join public.data_sources s on s.key = l.source;

-- Each city bike crash with the nearest lane segment within 25 m, if any.
--   facility_status: 'in_place'       the lane was installed in an earlier year than the crash
--                    'before_install' the crash came before the year the lane was installed
--                    'install_year'   same year: can't tell, so the website leaves it out
--                    null             no mapped lane within 25 m
-- Ties (a crash at an intersection where two segments meet) go to the lower source_record_id,
-- so the result is stable. The website repeats these rules in web/src/lib/cityStreets.ts for
-- its offline fixtures; keep the two in step.
create view public.public_crash_facility_context
with (security_barrier = true) as
with segments as (
  select
    f.id,
    f.source_record_id,
    f.facility_code,
    f.install_year,
    (a.point ->> 1)::float8                                     as a_lat,
    (a.point ->> 0)::float8                                     as a_lon,
    (f.route -> 'coordinates' -> (a.idx::integer) ->> 1)::float8 as b_lat,
    (f.route -> 'coordinates' -> (a.idx::integer) ->> 0)::float8 as b_lon
  from public.bike_facilities f
  cross join lateral jsonb_array_elements(f.route -> 'coordinates') with ordinality as a(point, idx)
  -- ordinality is 1-based, so element idx (0-based) is the next point.
  where a.idx < jsonb_array_length(f.route -> 'coordinates')
)
select
  c.source,
  c.source_record_id,
  c.occurred_at,
  near.facility_source_record_id,
  near.facility_code,
  t.protection,
  near.install_year,
  round(near.distance_m::numeric, 1)::float8 as distance_m,
  case
    when near.facility_code is null or near.install_year is null then null
    when near.install_year < extract(year from c.occurred_at) then 'in_place'
    when near.install_year > extract(year from c.occurred_at) then 'before_install'
    else 'install_year'
  end as facility_status
from public.public_crash_records c
left join lateral (
  select d.facility_source_record_id, d.facility_code, d.install_year, d.distance_m
  from (
    select
      s.source_record_id as facility_source_record_id,
      s.facility_code,
      s.install_year,
      public.segment_distance_m(c.latitude, c.longitude, s.a_lat, s.a_lon, s.b_lat, s.b_lon) as distance_m
    from segments s
    -- Cheap box filter first (about 25 m), then the exact distance.
    where least(s.a_lat, s.b_lat) <= c.latitude + 0.000226
      and greatest(s.a_lat, s.b_lat) >= c.latitude - 0.000226
      and least(s.a_lon, s.b_lon) <= c.longitude + 0.000305
      and greatest(s.a_lon, s.b_lon) >= c.longitude - 0.000305
  ) d
  where d.distance_m <= 25
  -- Rounded to the centimeter first, so two segments meeting at a point tie exactly instead of
  -- by floating-point noise.
  order by round(d.distance_m::numeric, 2), d.facility_source_record_id
  limit 1
) near on true
left join public.bike_facility_types t on t.code = near.facility_code
where c.mode = 'bike';

revoke all on public.public_bike_facilities, public.public_bike_count_years,
  public.public_bike_count_locations, public.public_crash_facility_context
  from public, anon, authenticated;
grant select on public.public_bike_facilities, public.public_bike_count_years,
  public.public_bike_count_locations, public.public_crash_facility_context to anon;
