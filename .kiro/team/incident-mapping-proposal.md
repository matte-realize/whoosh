# Proposal: Incident mapping (Role C)

Status: DEFAULTS ACCEPTED by Role C, October 24, 2026; awaiting the iOS owner on decisions 3
and 5. Built: migration `supabase/migrations/20261024130000_incident_mapping_and_indexes.sql`
and tests `supabase/tests/incident_cells.test.sql` (20 assertions) pass on the local database.
The website shows the cells as a layer of the community map
(`web/src/components/CommunityMapSection.tsx`, sample data in `web/fixtures/incident_cells.json`),
written but not yet built or type-checked. Companion to `supabase-contract.md`,
`hazard-contract.md`, and `privacy.md`.

## 1. What it is

A public map on the website that shows **where riders reported or the app detected incidents**
(close vehicle events), aggregated across riders. It supports the product vision items
"near-miss logging and reporting" and "bike-infrastructure analysis". It is a map of reports,
not a measurement of how dangerous a street is.

## 2. Why this needs more than a view of `near_misses`

`privacy.md` says public website data must come from an explicit, reviewed view and never from
raw tables. A near-miss row carries a precise latitude, longitude and timestamp. Published
as-is, a pattern of points near a rider's route start can show where they live or work, and a
fresh point shows where they are right now. The trimmed route protects the start and end of a
ride, but nothing yet protects an incident that sits near them.

So the public layer is **aggregated, thresholded and delayed**, and it only includes incidents
the rider opted in to share.

## 3. Honest framing (applies to the site, the pitch and the app)

- Two sources, shown separately: **rider-reported** (the rider marked it) and **auto-detected**
  (experimental vehicle detection). Detected events are unvalidated and include false alarms.
- The legend says "unverified reports", not "dangerous spots".
- No claim that an area is safe because it shows no incidents. Few riders means few reports.
- A count is not a rate. We do not know how many riders passed through each place, so the map
  cannot say one street is worse than another. Exposure counts are a possible later feature.
- A single camera cannot measure distance. "Close pass" stays a human judgment
  (`vision/LABELING.md`).

## 4. Design

### 4.1 Data changes (new migration; the existing three stay as they are)

On `near_misses`:

| Change | Reason |
| ------ | ------ |
| `source text not null default 'detected'`, check in `('detected', 'rider_reported')` | Tells the two apart. `kind` stays the vehicle type. |
| `confidence` becomes nullable (the 0..1 check stays) | A rider report has no detector score. Storing 1.0 would misrepresent it. |
| `share_publicly boolean not null default false` | An incident is public only if its own flag is true. Sharing a ride does not share its incidents. |

The app sets `source` and `share_publicly` on upload. The existing RLS and the ride-ownership
check still apply. Grants for `anon` on `near_misses` stay none.

### 4.2 The public view `public_incident_cells`

Reviewed, owner-rights, `anon` can read the view only (same pattern as `public_rides`).

- **Grid snapping:** coordinates are rounded to 3 decimals (about 110 m north-south, about 80 m
  east-west at Boston's latitude). The view returns the cell center, never an original point.
- **Threshold:** a cell appears only if it holds at least **3 shared incidents from at least
  2 different riders** (counted inside the view; `user_id` is never output).
- **Delay:** only incidents older than **24 hours** count, so the map cannot show where a rider
  was a moment ago.
- **Output columns only:** cell latitude, cell longitude, incident count, count by source,
  count by vehicle kind, and the first and last month with an incident. No `user_id`, `ride_id`,
  exact time, or confidence.
- **Not exposed:** raw near misses, individual points, and anything with a time of day.

The numbers 3, 2 and 24 hours are **starting values for the team to approve**. They reduce
re-identification risk and do not remove it. With few riders, one person's habits can still
stand out, which is why the thresholds count distinct riders.

### 4.3 Website

- An "Incidents" layer on the existing map: one circle per cell, sized by count, with a text
  label of the count (not color alone), and a legend with the two sources.
- A visible note: "Unverified reports and experimental detections from opted-in riders. Not a
  safety rating."
- Fixtures mode shows clearly marked sample cells, because a small demo group will not pass the
  thresholds with real data. The demo plan says so out loud.

### 4.4 App responsibilities (the iOS owner; not enforced by the database)

- **Drop incidents inside the privacy-trim zone** (the first and last 160 m of the ride) before
  upload. The database cannot check this reliably, because the stored route is already trimmed
  and is a JSON line, not a spatial type.
- A separate, off-by-default opt-in: "Contribute incidents to the public map", with plain text
  about what becomes public (grid-snapped place, vehicle type, month; no name or account).
- A way for the rider to **mark a near miss** safely (for example a handlebar button, a voice
  command, or a button used after stopping). Never while riding with hands off the bars.
- Deleting a ride deletes its incidents (already true: `on delete cascade`).

### 4.5 Contracts to update if approved

- `supabase-contract.md`: the new columns, the view, its grants, and the thresholds.
- `hazard-contract.md`: `source` added to the mapping table, and the rider-reported event.
- `ios-share-toggle-proposal.md`: a second, separate opt-in for incidents.

## 5. Tests (written with the migration, run locally)

pgTAP additions to `supabase/tests/`:
- Cell with 2 incidents, or 3 incidents from one rider: not shown.
- Cell with 3 incidents from 2 riders: shown, with the right count.
- Unshared incidents are never counted, even in an otherwise qualifying cell.
- Incidents younger than 24 hours are not counted.
- The view has no `user_id`, `ride_id`, exact time, or confidence column.
- `anon` can read the view and cannot read `near_misses`; `authenticated` cannot read the view.
- A rider-reported incident with no confidence inserts successfully.

## 6. Decisions needed

1. **Opt-in per incident, separate from sharing a ride?** Proposed: yes.
2. **Thresholds:** 3 incidents and 2 riders per cell, 24-hour delay, about 100 m cells. Approve
   or change.
3. **Rider-reported incidents in scope?** They need an in-app way to mark one, which is iOS work.
   If not, drop `source` and keep detected events only.
4. **Who may see the map?** Anyone with the link (proposed), or only team members during the demo.
5. **Does the app drop incidents near the start and end of a ride?** The iOS owner must agree,
   because the database cannot do it.

## 7. Risks

- **Too few riders:** at the hackathon almost no real cell will pass the thresholds. The live
  map will look empty, and the demo uses sample data, labeled as such.
- **Re-identification:** thresholds and snapping help but do not guarantee anonymity. Do not
  describe the map as "anonymous" or "private" without qualification.
- **False alarms:** auto-detected events can be wrong. The map says so and separates them.
- **Misuse as a safety rating:** the copy and the legend must not invite it.
