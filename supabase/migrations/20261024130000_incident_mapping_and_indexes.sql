-- Incident mapping (near_misses changes + public_incident_cells view) and performance indexes.
-- Source: .kiro/team/incident-mapping-proposal.md (defaults approved October 24, 2026).
-- A new migration on purpose: the three earlier migrations are already applied locally, so they
-- are not edited.

-- ---------------------------------------------------------------------------
-- 1. near_misses: incident source, optional confidence, per-incident sharing
-- ---------------------------------------------------------------------------

alter table public.near_misses
  add column source text not null default 'detected',
  add column share_publicly boolean not null default false,
  alter column confidence drop not null;

alter table public.near_misses
  add constraint near_misses_source_check
    check (source in ('detected', 'rider_reported')),
  -- A detector event always has a score. A rider report has none, and storing 1.0 would
  -- misrepresent it. The existing 0..1 check still applies whenever a value is present.
  add constraint near_misses_detected_has_confidence
    check (source = 'rider_reported' or confidence is not null);

-- ---------------------------------------------------------------------------
-- 2. Performance indexes
-- ---------------------------------------------------------------------------

-- RLS on near_misses filters every select/update/delete by user_id = auth.uid(). Without this
-- index each request scans the table. It also covers the user_id foreign key to auth.users,
-- which Supabase's performance advisor flags as unindexed.
create index near_misses_user_id_idx on public.near_misses (user_id);

-- The website reads public_rides ordered by started_at desc, limit 50, and only shared rides
-- qualify. A partial index holds just those rows in that order.
create index rides_shared_started_at_idx on public.rides (started_at desc)
  where share_publicly;

-- public_incident_cells only reads shared incidents older than 24 hours. A partial index on
-- occurred_at keeps that scan to shared rows.
create index near_misses_shared_occurred_at_idx on public.near_misses (occurred_at)
  where share_publicly;

-- ---------------------------------------------------------------------------
-- 3. public_incident_cells: the only incident data the website (anon) may read
-- ---------------------------------------------------------------------------
--
-- Privacy rules (all three must hold before a cell appears):
--   * Snapping: coordinates are rounded to 3 decimals (about 110 m north-south, about 80 m
--     east-west at Boston's latitude). The rounded point is returned, never an original point.
--   * Threshold: at least 3 shared incidents from at least 2 different riders in the cell.
--   * Delay: only incidents older than 24 hours count.
-- Output has no user_id, ride_id, exact time, confidence, or time of day. Months only.
--
-- Same deliberate choice as public_rides: the view runs with its owner's rights so it can read
-- near_misses past RLS, and `anon` has no privilege on the table itself. The WHERE and HAVING
-- clauses are the access rule. Any change to them needs review.
--
-- Known limit: thresholds reduce re-identification risk and do not remove it. A user with two
-- anonymous accounts could add their own incidents to a cell to learn whether another rider
-- reported one there. Captcha and rate limits on anonymous sign-in make that harder. Do not call
-- the map anonymous without qualification.
--
-- Performance: this aggregates on every read. That is fine at hackathon scale. If it grows,
-- replace it with a materialized view refreshed on a schedule (which also removes the per-read
-- cost of the distinct-rider count).

create view public.public_incident_cells
with (security_barrier = true) as
with eligible as (
  select
    round(latitude::numeric, 3)  as cell_latitude,
    round(longitude::numeric, 3) as cell_longitude,
    user_id,
    source,
    kind,
    occurred_at
  from public.near_misses
  where share_publicly
    and occurred_at < now() - interval '24 hours'
)
select
  cell_latitude::float8                                 as latitude,
  cell_longitude::float8                                as longitude,
  count(*)                                              as incident_count,
  count(*) filter (where source = 'rider_reported')     as rider_reported_count,
  count(*) filter (where source = 'detected')           as detected_count,
  array_agg(distinct kind order by kind)                as vehicle_kinds,
  date_trunc('month', min(occurred_at))::date           as first_month,
  date_trunc('month', max(occurred_at))::date           as last_month
from eligible
group by cell_latitude, cell_longitude
having count(*) >= 3
   and count(distinct user_id) >= 2;

-- Nothing for anyone by default, then read-only for anon (the website). Not for authenticated:
-- the website never signs in.
revoke all on public.public_incident_cells from public, anon, authenticated;
grant select on public.public_incident_cells to anon;
