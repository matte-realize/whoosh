# Supabase Contract — Whoosh

**Status: DRAFT.** Owned by Role C. The iOS app implements sync (tasks 21–23) only after
this is marked **Agreed** by C and the iOS owner. Change it through a quick review, then
bump the version.

Version: 0.2 (draft, October 24, 2026)

## Auth

- Supabase **anonymous sign-in** enabled. Each install gets an anonymous `auth.uid()`.
  Enable it in the dashboard, or with `[auth] enable_anonymous_sign_ins = true` in
  `supabase/config.toml` (not yet created). Captcha is recommended to limit abuse of
  anonymous sign-ins.
- No email, name, or other PII.
- The app uses only the **public client key**: the new publishable key (`sb_publishable_...`),
  or the legacy `anon` JWT while it still works. The secret key (`sb_secret_...`) or legacy
  `service_role` key never goes in the app or in Git; it stays in C's server/CI environment.
- Supabase is deprecating the legacy keys by end of 2026
  ([migration guide](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys)).

## Units and formats

- All stored values are SI: meters, seconds, meters/second. The website converts to
  miles/mph for display.
- Timestamps are `timestamptz` in UTC.
- Routes are GeoJSON `LineString` (`[longitude, latitude]` order) stored as `jsonb`. They are
  already privacy-trimmed by the app before upload (160 m from each end by default).
- Route storage: `jsonb` is the proposed choice for now. PostGIS is deferred.

## Tables

### `rides`

| Column              | Type        | Notes                                          |
| ------------------- | ----------- | ---------------------------------------------- |
| `id`                | uuid PK     | Generated on-device, no server default; upserts are idempotent |
| `user_id`           | uuid        | Not null, `default auth.uid()`, references `auth.users` (`on delete cascade`) |
| `started_at`        | timestamptz | Not null                                       |
| `ended_at`          | timestamptz | Not null; check `ended_at >= started_at`       |
| `distance_m`        | float8      | Not null, `>= 0`. Full-ride distance (computed before trimming) |
| `active_duration_s` | float8      | Not null, `>= 0`. Excludes paused time         |
| `avg_speed_mps`     | float8      | Not null, `>= 0`                               |
| `route`             | jsonb       | Not null; check `route ->> 'type' = 'LineString'`. Trimmed GeoJSON |
| `app_version`       | text        | For debugging contract drift                   |
| `created_at`        | timestamptz | Not null, `default now()`                      |
| `share_publicly`    | boolean     | Not null, `default false`. The app sets it from a separate opt-in toggle |

### `near_misses` (future, not used by the MVP app)

| Column           | Type        | Notes                                           |
| ---------------- | ----------- | ----------------------------------------------- |
| `id`             | uuid PK     | `default gen_random_uuid()`                     |
| `ride_id`        | uuid FK     | Not null, references `rides.id`, `on delete cascade` |
| `user_id`        | uuid        | Not null, `default auth.uid()`                  |
| `occurred_at`    | timestamptz | Not null. From `HazardDetection.timestamp`      |
| `latitude`       | float8      | Not null. Nearest accepted route point          |
| `longitude`      | float8      | Not null                                        |
| `kind`           | text        | Not null. From `HazardDetection.kind` (e.g. `vehicle`) |
| `confidence`     | float8      | Not null; check `between 0 and 1`               |
| `position_hint`  | text null   | Check: `left` / `center` / `right`, or null     |

## Grants (required on every table)

Supabase no longer grants Data API access to new tables in `public` automatically. New projects
work this way since May 30, 2026, and existing projects switch on October 30, 2026
([changelog](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)).
Without an explicit `GRANT`, the Data API returns `42501 permission denied for table`, before
RLS is consulted. Every migration therefore states its grants in the same file as the table:

| Object | `authenticated` | `anon` | `service_role` |
| ------ | --------------- | ------ | -------------- |
| `rides` | select, insert, update, delete | none | select, insert, update, delete |
| `near_misses` | select, insert, update, delete | none | select, insert, update, delete |
| `public_rides` (view) | none | select | none |

Grants only decide whether a role can touch the table. RLS still decides which rows. Do not
fix a `42501` by granting `anon` access to a raw table.

## Row Level Security (required on every table)

Implemented in `supabase/migrations/20261024120000_rides.sql` and
`supabase/migrations/20261024120100_near_misses.sql`. Policies apply `to authenticated`
(anonymous sign-in users have that role) and use `(select auth.uid())` so Postgres evaluates
it once per statement:

```sql
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
```

`near_misses` has the same four policies (`"own near_misses: ..."`). Its insert and update
policies additionally require that `ride_id` refers to a ride owned by the same user
(`exists (select 1 from public.rides r where r.id = near_misses.ride_id and r.user_id =
(select auth.uid()))`), so a near miss cannot be attached to someone else's ride.

## Website access

The website must not bypass RLS on raw tables to show other users' rides. Options:

1. **Per-user view:** the website signs in anonymously too and shows only that browser's
   rides (simplest, but it won't show the phone's rides).
2. **Public demo view (recommended for the demo):** a reviewed SQL view exposing only trimmed
   routes and summary stats, no `user_id`, readable by `anon`. Rides opt in through the
   `share_publicly` column that the app sets from a separate toggle.

**Proposed, pending Role C sign-off: option 2.** The view `public_rides` exposes `id`,
`started_at`, `distance_m`, `active_duration_s`, `avg_speed_mps`, and `route` (no `user_id`)
for rows where `share_publicly = true`, and `anon` gets `select` on the view only. The view is
written in `supabase/migrations/20261024120200_public_rides_view.sql` (it also revokes all
direct `anon` access to `rides` and `near_misses`). It has been applied and tested on a local
database only. Update this section if C picks differently.

## App behavior the backend can rely on

- Upload happens only after the ride is saved locally, and only with sync enabled.
- `upsert` on `id`, so retries never create duplicates.
- Deleting a ride in the app sends a `delete` by `id` (retried if offline).

## Open items for C

- [ ] Sign off on the website access option (proposed: public demo view). The view is written (B3).
- [ ] The iOS spec has no "share publicly" toggle (proposal: `ios-share-toggle-proposal.md`).
      Requirement 12 only covers the sync toggle.
      Until the iOS owner adds one (a separate opt-in, off by default, that sets
      `share_publicly`), no synced ride will appear on the website. For the demo, a ride can
      be flipped to shared manually in the dashboard.
- [ ] The `public_rides` view runs with owner rights, which Supabase's security advisor may
      flag. Decide whether to keep it or switch to the column-grant alternative described in the
      migration's comments.
- [ ] Confirm GeoJSON `jsonb` vs PostGIS `geography(LineString)` (PostGIS adds spatial
      queries for future infrastructure analysis; `jsonb` is simpler to start).
- [x] `near_misses` insert/update policies now check that `ride_id` belongs to the same user
      (assertions 27 and 29 cover insert and re-point). Passes locally.
- [x] Explicit Data API grants added to all three migrations (see "Grants"). Applied and
      tested locally. Not yet checked on a hosted project.
- [ ] Confirm which API key type the project issued, and align the iOS variable name
      (`SUPABASE_ANON_KEY` in spec files vs `SUPABASE_PUBLISHABLE_KEY`).
- [x] Run and validate the migrations locally: `supabase db reset` applies all three, and
      `supabase test db` passes all 34 assertions in `supabase/tests/rls_rides.test.sql`
      (October 24, 2026).
- [ ] Apply to the real project: `supabase link`, `supabase db push --dry-run`, then push.
      Re-check isolation with two real anonymous sessions, and enable anonymous sign-ins in
      the project.
- [ ] Mark this document **Agreed** and set version 1.0.
