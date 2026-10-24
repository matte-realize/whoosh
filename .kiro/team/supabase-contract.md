# Supabase Contract — Whoosh

**Status: DRAFT.** Owned by Role C. The iOS app implements sync (tasks 21–23) only after
this is marked **Agreed** by C and the iOS owner. Change it through a quick review, then
bump the version.

Version: 0.1 (draft, October 24, 2026)

## Auth

- Supabase **anonymous sign-in** enabled. Each install gets an anonymous `auth.uid()`.
- No email, name, or other PII.
- The app uses only the **anon key**. The `service_role` key stays in C's server/CI
  environment and is never committed.

## Units and formats

- All stored values are SI: meters, seconds, meters/second. The website converts to
  miles/mph for display.
- Timestamps are `timestamptz` in UTC.
- Routes are GeoJSON `LineString` (`[longitude, latitude]` order) stored as `jsonb`. They are
  already privacy-trimmed by the app before upload (160 m from each end by default).

## Tables

### `rides`

| Column              | Type        | Notes                                          |
| ------------------- | ----------- | ---------------------------------------------- |
| `id`                | uuid PK     | Generated on-device; upserts are idempotent    |
| `user_id`           | uuid        | `default auth.uid()`, references `auth.users`  |
| `started_at`        | timestamptz |                                                |
| `ended_at`          | timestamptz |                                                |
| `distance_m`        | float8      | Full-ride distance (computed before trimming)  |
| `active_duration_s` | float8      | Excludes paused time                           |
| `avg_speed_mps`     | float8      |                                                |
| `route`             | jsonb       | Trimmed GeoJSON LineString                     |
| `app_version`       | text        | For debugging contract drift                   |
| `created_at`        | timestamptz | `default now()`                                |

### `near_misses` (future, not used by the MVP app)

| Column           | Type        | Notes                                           |
| ---------------- | ----------- | ----------------------------------------------- |
| `id`             | uuid PK     |                                                 |
| `ride_id`        | uuid FK     | References `rides.id`, `on delete cascade`      |
| `user_id`        | uuid        | `default auth.uid()`                            |
| `occurred_at`    | timestamptz | From `HazardDetection.timestamp`                |
| `latitude`       | float8      | Nearest accepted route point                    |
| `longitude`      | float8      |                                                 |
| `kind`           | text        | From `HazardDetection.kind` (e.g. `vehicle`)    |
| `confidence`     | float8      | 0...1                                           |
| `position_hint`  | text null   | `left` / `center` / `right`                     |

## Row Level Security (required on every table)

```sql
alter table rides enable row level security;

create policy "own rides: select" on rides for select using (user_id = auth.uid());
create policy "own rides: insert" on rides for insert with check (user_id = auth.uid());
create policy "own rides: update" on rides for update using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy "own rides: delete" on rides for delete using (user_id = auth.uid());
```

Same pattern for `near_misses`.

## Website access

The website must not bypass RLS on raw tables to show other users' rides. Options, to be
decided by C:

1. **Per-user view:** the website signs in anonymously too and shows only that browser's
   rides (simplest, but it won't show the phone's rides).
2. **Public demo view (recommended for the demo):** a reviewed SQL view exposing only trimmed
   routes and summary stats, no `user_id`, readable by `anon`. Rides opt in through a
   `share_publicly boolean default false` column that the app sets from a separate toggle.

Whichever C picks, update this section before marking the contract Agreed.

## App behavior the backend can rely on

- Upload happens only after the ride is saved locally, and only with sync enabled.
- `upsert` on `id`, so retries never create duplicates.
- Deleting a ride in the app sends a `delete` by `id` (retried if offline).

## Open items for C

- [ ] Choose a website access option and finalize the `share_publicly` column if needed.
- [ ] Confirm GeoJSON `jsonb` vs PostGIS `geography(LineString)` (PostGIS adds spatial
      queries for future infrastructure analysis; `jsonb` is simpler to start).
- [ ] Mark this document **Agreed** and set version 1.0.
