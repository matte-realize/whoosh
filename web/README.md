# Whoosh web dashboard

A small Next.js 16 (App Router, React 19, TypeScript) site that lists shared rides and draws the
selected route on a Leaflet map with OpenStreetMap tiles. Distances and speeds are stored in SI
units and shown in miles and mph.

## Run it

Requires Node >= 22.

```sh
cd web
cp .env.example .env.local
npm install
npm run dev
```

Open http://localhost:3000 for the project page and http://localhost:3000/dashboard for the live
dashboard. `npm run typecheck` runs `tsc --noEmit`.

The project page's feature statuses come from `src/lib/projectStatus.ts`. Update that file
before a demo so the page never claims more than has been tested.

The first `npm install` creates `package-lock.json`. Commit it so everyone gets the same
dependency versions. It is not included yet because it was not possible to generate one here.

## Data modes

Set `NEXT_PUBLIC_DATA_SOURCE` in `.env.local`:

- `fixtures` (default): reads `fixtures/rides.json`. No Supabase project and no key needed. Only
  rides with `share_publicly: true` are shown, to match the real public view. The map tiles need
  internet access; offline, routes still draw on a blank background.
- `supabase`: reads the `public_rides` view. Set `NEXT_PUBLIC_SUPABASE_URL` and
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (the legacy anon key also works) in `.env.local`, then
  restart `npm run dev`. If either is missing, the page shows a configuration message.

To switch to Supabase: apply the migrations (including `20261024120200_public_rides_view.sql`),
share at least one ride, put the URL and publishable key in `.env.local`, and set
`NEXT_PUBLIC_DATA_SOURCE=supabase`.

Never put the secret or `service_role` key in `web/`. `NEXT_PUBLIC_` values are sent to every
browser.

## Page layout

1. **Totals** from the `public_stats` view: shared rides, distance, riding time, riders (shown
   only when at least 3 riders have shared rides), and mapped incident reports. In fixtures mode
   the same totals are computed from the sample files, with the rider count unknown.
2. **Community map:** every shared route (blue lines, thinned to 300 points each for drawing)
   and the incident cells from `public_incident_cells` (orange circles), each as a layer you can
   turn off with the control at the top right. Each cell is about 100 m with at least 3 reports
   from at least 2 riders, delayed by a day. Individual incidents are never sent to the browser.
   With only a few real riders, expect the live incident layer to be empty.
3. **Shared rides:** the list and the selected ride's full route.

The rides and incident cells are each fetched once per page load and shared by all three parts.

## Data and privacy

- The site reads only the `public_rides` view, as role `anon`. It never signs in.
- It shows only rides the rider opted in to share.
- Routes arrive already trimmed by the app (160 m from each end by default). The site does not
  receive `user_id`, `ended_at`, `app_version`, or `created_at`.
- There are no analytics or tracking scripts. The browser contacts Supabase (in `supabase`
  mode) and OpenStreetMap's tile server.
- Near-miss markers appear only in fixtures mode, labeled "experimental vehicle detections
  (sample data)". The `near_misses` table is not readable by `anon`, so Supabase mode shows none.
  Whether to add a public near-miss view is an open decision for Role C.
