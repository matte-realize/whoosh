-- Real public crash data, with provenance, next to Whoosh's own rider data.
--
-- WHY
--   Rider-shared data starts near zero. Cities already publish crash records, so the map can show
--   real history from day one, and Whoosh reports can be compared against it.
--
-- WHAT
--   data_sources           one row per external dataset: publisher, URL, license, coverage dates.
--   public_crash_records   one row per published record, keyed by (source, source_record_id), so
--                          re-imports update rows in place instead of duplicating them.
--   public_crash_points    the view the website reads (anon): the published fields only.
--   public_street_cells    the view that joins both worlds per ~100 m cell: city crash counts and
--                          Whoosh rider reports (from public_incident_cells, already thresholded).
--
-- PRIVACY
--   These are public, de-identified city records (no names, plates, or severity). Nothing here is
--   rider data. Rider data still reaches the website only through the thresholded views.
--
-- LOADING
--   Data comes from supabase/data/<source>/import.py, which writes upserts. The first snapshot is
--   applied by migration 20261024160100. Clients never write these tables.

-- ---------------------------------------------------------------------------
-- 1. data_sources
-- ---------------------------------------------------------------------------

create table public.data_sources (
  key            text primary key,
  name           text not null,
  publisher      text not null,
  url            text not null,
  license        text not null,
  -- When we last pulled from the source, and the last date the source says it covers.
  retrieved_on   date not null,
  data_through   date,
  notes          text,
  updated_at     timestamptz not null default now(),

  constraint data_sources_key_format check (key ~ '^[a-z0-9_]{2,40}$'),
  constraint data_sources_url_https check (url ~ '^https://')
);

-- ---------------------------------------------------------------------------
-- 2. public_crash_records
-- ---------------------------------------------------------------------------

create table public.public_crash_records (
  id               bigint generated always as identity primary key,
  source           text not null references public.data_sources (key) on update cascade,
  -- The record's id in the source dataset (text, because sources differ).
  source_record_id text not null,
  -- Boston: when responders were dispatched, not the crash itself.
  occurred_at      timestamptz not null,
  -- The most vulnerable person involved: bike, ped, or mv (motor vehicle only).
  mode             text not null,
  location_type    text,
  street           text,
  cross_street_1   text,
  cross_street_2   text,
  latitude         float8 not null,
  longitude        float8 not null,
  imported_at      timestamptz not null default now(),

  constraint public_crash_records_source_record_key unique (source, source_record_id),
  constraint public_crash_records_mode_check check (mode in ('bike', 'ped', 'mv')),
  constraint public_crash_records_latitude_range check (latitude between -90 and 90),
  constraint public_crash_records_longitude_range check (longitude between -180 and 180),
  constraint public_crash_records_text_lengths check (
    coalesce(char_length(street), 0) <= 120
    and coalesce(char_length(cross_street_1), 0) <= 120
    and coalesce(char_length(cross_street_2), 0) <= 120
    and coalesce(char_length(location_type), 0) <= 40
  )
);

-- The map and the cell view filter by mode and read coordinates.
create index public_crash_records_mode_idx on public.public_crash_records (mode, occurred_at desc);
-- Street-level summaries ("Mass Ave between Columbus and St. Botolph").
create index public_crash_records_street_idx on public.public_crash_records (street, cross_street_1, cross_street_2);

-- ---------------------------------------------------------------------------
-- 3. Grants and RLS
-- ---------------------------------------------------------------------------
--
-- The tables are written only by imports (postgres / service_role). The website reads the views.

revoke all on table public.data_sources, public.public_crash_records from public, anon, authenticated;
grant all on table public.data_sources, public.public_crash_records to service_role;

alter table public.data_sources enable row level security;
alter table public.public_crash_records enable row level security;

-- ---------------------------------------------------------------------------
-- 4. Views for the website (anon)
-- ---------------------------------------------------------------------------

-- Every published field the website needs, plus attribution, and nothing internal.
create view public.public_crash_points
with (security_barrier = true) as
select
  r.source,
  r.source_record_id,
  r.occurred_at,
  r.mode,
  r.street,
  r.cross_street_1,
  r.cross_street_2,
  r.latitude,
  r.longitude,
  s.name    as source_name,
  s.license as source_license,
  s.url     as source_url
from public.public_crash_records r
join public.data_sources s on s.key = r.source;

-- Public view of the sources themselves, for attribution on the site.
create view public.public_data_sources
with (security_barrier = true) as
select key, name, publisher, url, license, retrieved_on, data_through, notes
from public.data_sources;

-- City crashes and Whoosh reports in the same ~100 m cells as public_incident_cells (3 decimals),
-- so a street can be read as "N reported crashes, M rider close calls".
-- Whoosh numbers come from public_incident_cells, which already applies the rider thresholds.
create view public.public_street_cells
with (security_barrier = true) as
with city as (
  select
    round(latitude::numeric, 3)  as cell_latitude,
    round(longitude::numeric, 3) as cell_longitude,
    count(*) filter (where mode = 'bike') as bike_crashes,
    count(*) filter (where mode = 'bike' and occurred_at >= now() - interval '5 years') as bike_crashes_5y,
    count(*) filter (where mode = 'ped') as ped_crashes,
    max(occurred_at) filter (where mode = 'bike') as last_bike_crash
  from public.public_crash_records
  group by 1, 2
),
whoosh as (
  select
    latitude::numeric  as cell_latitude,
    longitude::numeric as cell_longitude,
    incident_count
  from public.public_incident_cells
)
select
  coalesce(c.cell_latitude, w.cell_latitude)::float8   as latitude,
  coalesce(c.cell_longitude, w.cell_longitude)::float8 as longitude,
  coalesce(c.bike_crashes, 0)                          as city_bike_crashes,
  coalesce(c.bike_crashes_5y, 0)                       as city_bike_crashes_5y,
  coalesce(c.ped_crashes, 0)                           as city_ped_crashes,
  date_trunc('month', c.last_bike_crash)::date         as last_city_bike_crash_month,
  coalesce(w.incident_count, 0)                        as whoosh_reports
from city c
full join whoosh w
  on w.cell_latitude = c.cell_latitude and w.cell_longitude = c.cell_longitude;

revoke all on public.public_crash_points, public.public_data_sources, public.public_street_cells
  from public, anon, authenticated;
grant select on public.public_crash_points, public.public_data_sources, public.public_street_cells to anon;
