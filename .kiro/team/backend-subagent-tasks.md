# Backend Subagent Tasks — Whoosh (Supabase)

Status: PLAN, not started. Companion to `supabase-contract.md` (the schema source of truth) and
`team-plan.md` (Role C). Written October 24, 2026.

Each task below is a self-contained brief that can be handed to one subagent
(`general-task-execution`) with no other context. Tasks marked **HUMAN** are not delegated.

## 0. Progress (October 24, 2026)

Local database: the three migrations apply with `supabase db reset`, and `supabase test db` passes
all 34 assertions (run by the user, October 24, 2026). Not yet done: applying to the hosted
project, running the website, and checking that the tests fail when a policy is removed.
Everything under `web/` is still unrun. The agent sandbox cannot run the Supabase CLI or Docker,
so these runs happen in the user's own terminal.

| Task | State | Files |
| ---- | ----- | ----- |
| B1 migrations | Authored | `supabase/migrations/20261024120000_rides.sql`, `…120100_near_misses.sql` |
| B2 RLS test | Authored | `supabase/tests/rls_rides.test.sql` |
| B3 public view | Authored | `supabase/migrations/20261024120200_public_rides_view.sql` (test extended, 26 assertions) |
| B4 seed data | Authored | `supabase/seed.sql`, `web/fixtures/rides.json` |
| B6 contract | Done, still DRAFT 0.2 | `.kiro/team/supabase-contract.md` |
| B5 website | Authored (Next.js 16, Leaflet + OpenStreetMap) | `web/` (never installed, built, or type-checked; needs Node >= 22) |
| `config.toml` | Created by `supabase init` | `enable_anonymous_sign_ins` is still `false` locally; the app needs `true`. Tests do not. |
| near_misses ownership fix | Authored | Insert/update policies check the ride belongs to the same user; assertions 27 and 29 |
| Data API grants | Authored | Explicit grants in all three migrations; required by Supabase's 2026 default change |
| Sharing-flow RLS tests | Done, passing locally | Assertions 30–34; the file has 34 assertions and clears seeded rides inside its transaction |
| HazardDetection contract draft | Authored, awaiting 3-way OK | `.kiro/team/hazard-contract.md` |
| Eval tooling for B | Done and run | `vision/eval/` (stdlib Python; `python3 run_toy.py`) |
| Demo script and runbook | Drafted, never rehearsed | `.kiro/team/demo-plan.md` |
| Incident map + indexes | Database done, passing locally (54 assertions across both test files); web part not yet built | Migration `20261024130000_…`, tests `incident_cells.test.sql` (20), web `IncidentSection` |
| Website map performance | Authored, not yet built | Map created once per page; ride switch only swaps the route layer; canvas renderer |
| iOS share-toggle proposal | Drafted, awaiting the iOS owner | `.kiro/team/ios-share-toggle-proposal.md` |

Next, by you: install the CLI (`brew install supabase/tap/supabase`), start Docker, run
`supabase init`, set `[auth] enable_anonymous_sign_ins = true`, then `supabase start`,
`supabase db reset` and `supabase test db`. Expect to fix small SQL errors on the first run.

## 1. Where Supabase integrates

Four touchpoints. Only the first two can start today, because the iOS project does not exist yet.

| # | Touchpoint | Location in repo | Owner | Blocked by |
| - | ---------- | ---------------- | ----- | ---------- |
| 1 | Schema, RLS, seed data (migrations) | `supabase/` (new, repo root) | Backend | Contract decisions (section 3) |
| 2 | Public demo view for the website | `supabase/migrations/` | Backend | Contract decision on website access |
| 3 | Website/dashboard | `web/` (new, stack TBD) | Backend | Touchpoints 1–2, Node install |
| 4 | iOS client: `RideSyncService`, `SyncCoordinator`, `SupabaseRideSyncService`, Settings toggle | `Whoosh/Services/Sync/`, `Whoosh/Support/AppConfig.swift`, composition root in `Whoosh/App/` | iOS (tasks 21–23) | iOS tasks 1–18, contract "Agreed" |

The iOS app reaches Supabase through exactly one place: `SupabaseRideSyncService`, injected at the
composition root only when the user turns sync on. Everything else in the app stays unaware of Supabase.

## 2. Keys and secrets (applies to every task)

Do not paste any key into chat or a subagent prompt. Subagents read keys from files that git ignores.

| Key | Where it lives | Notes |
| --- | -------------- | ----- |
| Publishable key (`sb_publishable_…`) or legacy `anon` key | iOS: `Secrets.xcconfig`. Web: `web/.env.local` | Safe to ship in a client. Both key types work side by side today. |
| Secret key (`sb_secret_…`) or legacy `service_role` | Developer shell env only | Never in the app, the website, or Git. Needed only for seeding/admin scripts. |
| CLI access token and DB password | Shell env (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`) | Needed only for the HUMAN remote-apply step. |

Known gotchas to pass to the iOS owner:
- In `.xcconfig`, `//` starts a comment, so write the URL as `https:/$()/<ref>.supabase.co`.
- The spec names the variable `SUPABASE_ANON_KEY`. If the project issued a publishable key, either
  keep the name or rename it to `SUPABASE_PUBLISHABLE_KEY` in `requirements.md`, `tasks.md` (task 1),
  `privacy.md`, and `tech.md` in one commit. Decision needed (section 3).
- `.gitignore` already covers `Secrets.xcconfig`, `.env`, and `.env.*` (except `.env.example`).

## 3. Decisions needed before tasks B1–B3 (defaults proposed)

| Decision | Default if you say "go" | Why |
| -------- | ----------------------- | --- |
| Which key type the project issued | Publishable key | Legacy keys are deprecated by end of 2026. |
| Route storage: `jsonb` GeoJSON or PostGIS | `jsonb` | Simpler; contract lists PostGIS as optional. |
| Website access: per-user view or public demo view | Public demo view with `share_publicly boolean default false` | Matches the contract's recommendation; shows the phone's rides on a big screen. |
| Website stack | Next.js or plain Vite + `@supabase/supabase-js` | Not chosen; Node is not installed yet. |

## 4. Prerequisites on this machine

Installed: Docker. Missing: Supabase CLI, `psql`, Node.

- `brew install supabase/tap/supabase` (needed for B1, B2, and the HUMAN remote step).
- Docker Desktop running (needed for `supabase start` in B2).
- Node via your preferred manager (needed only for B4).

## 5. Subagent task briefs

### B1. Local Supabase project and migrations

Goal: create the schema from `supabase-contract.md` as local migrations. No remote changes.

- Run `supabase init` at the repo root. In `supabase/config.toml`, enable anonymous sign-ins
  (`[auth] enable_anonymous_sign_ins = true`; confirm the key name against the CLI config reference).
- Create `supabase/migrations/<timestamp>_rides.sql`: the `rides` table exactly as the contract
  specifies, RLS enabled, the four per-operation policies using `user_id = auth.uid()`.
  Add `share_publicly boolean not null default false` if the default in section 3 is accepted.
- Create `<timestamp>_near_misses.sql` the same way, with `on delete cascade` to `rides`.
- Index `rides (user_id, started_at desc)`.
- Do not touch `supabase-contract.md`, do not run `supabase link` or `db push`.
- Done when: `supabase db reset` applies cleanly and `\d rides` matches the contract.
- Needs: Supabase CLI, Docker.

### B2. RLS verification

Goal: prove one anonymous user cannot read, update, or delete another user's rows.

- Add `supabase/tests/rls_rides.test.sql` (pgTAP, run with `supabase test db`) that creates two
  users, inserts a ride as user A, and asserts user B sees zero rows and cannot update or delete it.
  Also assert an insert with someone else's `user_id` is rejected, and that `anon` without a session
  sees nothing.
- Done when: `supabase test db` passes; deliberately dropping a policy makes it fail.
- Depends on: B1.

### B3. Public demo view (only if "public demo view" is chosen)

Goal: expose trimmed routes and summary stats for rides with `share_publicly = true`, without `user_id`.

- Migration `<timestamp>_public_rides_view.sql`: view `public_rides` selecting `id, started_at,
  distance_m, active_duration_s, avg_speed_mps, route` where `share_publicly`. Use
  `security_invoker = false` only if reviewed; document the choice in a SQL comment. Grant `select`
  to `anon` on the view only; revoke direct table access for `anon`.
- Extend B2's test: `anon` can read the view, sees only shared rides, and cannot read `rides`.
- Depends on: B1, B2.

### B4. Seed fixtures

Goal: realistic rows for the website and for tests before the app syncs anything.

- `supabase/seed.sql` with 3–5 rides (US-area coordinates, SI units, trimmed LineString) and a few
  `near_misses`; one ride shared, others not.
- `web/fixtures/rides.json` with the same data in the shape the website consumes.
- Depends on: B1.

### B5. Website scaffold

Goal: a minimal page that lists rides and draws a selected route on a map.

- Stack per section 3. Read `VITE_`/`NEXT_PUBLIC_` env vars from `web/.env.local`; commit
  `web/.env.example` with placeholders only.
- Reads `public_rides` through the publishable key only. No secret key anywhere in `web/`.
- Convert to miles/mph for display (storage stays SI). Copy follows the honest-copy rule in
  `privacy.md` (no "prevents/predicts collisions").
- Works against `web/fixtures/rides.json` with no network.
- Depends on: B3, B4. Needs Node.

### B6. Contract update (draft only)

Goal: reflect decisions from section 3 in `supabase-contract.md` as a proposed diff.

- Update the website-access section, the `share_publicly` column, the key naming, and the open
  items list. Leave status as DRAFT and version at 0.2. Marking it "Agreed" is HUMAN.
- Depends on: section 3 decisions.

### H1. HUMAN: apply to the real project

Not delegated. After B1–B3 pass locally:
1. Enable anonymous sign-ins in the dashboard (consider captcha to limit abuse).
2. `supabase link --project-ref <ref>`, review `supabase db push --dry-run`, then push.
3. Re-run the RLS checks against the remote with two real anonymous sessions.
4. Mark the contract "Agreed" at version 1.0.

### H2. iOS sync (tasks 21–23)

Stays with the iOS owner and stays in `tasks.md`. Starts after iOS task 18 and H1 step 4.
Inputs it needs from this plan: the agreed contract, key naming from section 2, and the
`Secrets.example.xcconfig` variable names.

## 6. Order and parallelism

```
decisions (section 3) ─ B1 ─┬─ B2 ─ B3 ─┬─ B5
                            ├─ B4 ──────┘
                            └─ B6
                         H1 (after B1–B3) ─ H2 (after iOS task 18)
```

B2/B4/B6 can run in parallel once B1 lands. B5 waits on B3 and B4.
