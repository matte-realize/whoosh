# Whoosh Demo Plan — Script and Runbook (Role C)

Status: DRAFT, October 24, 2026. Nothing in this plan has been rehearsed. Items marked
**verify** depend on work that has not been run yet (SQL, website, iOS app, detector).
Placeholders in `[brackets]` are filled in by a person, never guessed.

Honesty rules from `privacy.md` and `product.md` apply to everything said and shown:
detection is **experimental**, nobody says it prevents or predicts collisions, and any
performance number comes from `vision/REPORT.md` with its sample size.

## 1. What each part of the demo can truthfully show

| Demo moment | Shows | Depends on | Status |
| ----------- | ----- | ---------- | ------ |
| Record a ride on the iPhone 14 | Start, pause, resume, stop; live route; summary; history | iOS tasks 1–15, 18 | verify |
| Works in airplane mode | Local-first: everything above with no network | iOS task 20 check | verify |
| Rider hears or feels a caution alert | Experimental rear-vehicle detection driving a haptic/audio alert | B's detector + a real `AlertManager` + iOS task 18 | verify, may not make it |
| Ride appears on the big screen | Website lists the ride and draws its route | Sync (iOS 21–23), share toggle, Supabase project, `public_rides` view | verify, stretch |
| Near-miss markers on the map | Markers from **sample data** (fixtures mode only) | `web/fixtures/rides.json` | works only in fixtures mode |
| Incident map | Aggregated cells (3+ reports, 2+ riders, 1-day delay) | `public_incident_cells`, or sample `web/fixtures/incident_cells.json` | live map will almost certainly be empty at the hackathon; show sample data and say so |

Two facts to keep straight on stage:
- The website's Supabase mode cannot show near misses (`anon` cannot read that table). Any
  near-miss markers on screen are sample data, and the page says so. Say that out loud.
- Live sync needs a "share publicly" toggle in the app that the iOS spec does not have yet. If
  it is missing on demo day, use the manual share step in section 4.

## 2. The 3-minute script (draft)

Adjust the timings to the slot you are given: `[slot length]`.

| Time | Who | Say / do | On screen |
| ---- | --- | -------- | --------- |
| 0:00 | Presenter | Cycling is dangerous because you can't see what's coming up behind you. Whoosh uses the phone you already own, no extra hardware. | Title slide or the app home screen |
| 0:20 | Presenter | Start a ride. "Local-first: it records with no account and no signal." | iPhone mirrored: Start Ride, live route |
| 0:50 | Presenter | Show airplane mode on, then pause and resume. | Control Center showing airplane mode, then the ride screen |
| 1:10 | Presenter | If the detector is ready: "With the rear camera on, an experimental detector looks for vehicles closing in from behind and gives a haptic cue." Trigger the cue. Say once: "experimental". | Detection events or the alert |
| 1:40 | Presenter | Stop the ride and show the summary: distance, time, average speed, route. | Summary screen |
| 2:00 | Role C | Switch to the big screen. "Rides the rider chooses to share show up on the dashboard, with the first and last 0.1 miles trimmed for privacy." | Website with the shared ride |
| 2:30 | Role C | "No accounts, no analytics. We built this so the rider owns their data, and you can delete a ride." | Website or a privacy slide |
| 2:45 | Presenter | Close: what is measured, what is next. Quote only numbers from `vision/REPORT.md`, for example "in our test of [N] events, [X] were detected". | Slide with the report numbers and sample size |

If the detector is not ready, cut the 1:10 moment and say plainly: "Detection is the next
milestone; here is how the app is built to take it." The demo still stands without it.

## 3. What to say and not say

| Say | Do not say |
| --- | ---------- |
| "Experimental vehicle detection" | "Prevents collisions", "predicts collisions", "keeps you safe" |
| "In our test of [N] events on [roads/conditions], it detected [X]" | Any rate or accuracy without the sample size next to it |
| "Rides stay on the phone unless you turn sharing on" | "Your data is never uploaded" (it is, once sync is on) |
| "The route is trimmed 0.1 miles at each end before sharing" | "Your location is private" in general |
| "Sample data" whenever near-miss markers appear on the site | Presenting fixture markers as real detections |
| "This is a hackathon prototype" | Claims about other phones, bikes, weather or roads we did not test |

## 4. Runbook

### 4.1 Two days before

- [ ] Supabase project is awake. Free-tier projects can pause after inactivity; open the dashboard
      and check. **verify**
- [x] Migrations applied and `supabase test db` passed locally (54 assertions, October 24, 2026).
- [ ] Migrations applied to the hosted project. **verify**
- [ ] Anonymous sign-ins enabled in the project. **verify**
- [ ] The website builds: `cd web && npm install && npm run typecheck && npm run build`. **verify**
- [ ] `package-lock.json` committed.
- [ ] A full dry run of the script on the real phone and real projector or screen.
- [ ] Decide the mode for the big screen (section 4.3) and write it here: `[fixtures | supabase]`.

### 4.2 One hour before

- [ ] Phone: charged, Low Power Mode off, screen auto-lock set to a long delay, Do Not Disturb
      on, location permission already granted, airplane mode off until the moment you toggle it.
- [ ] Laptop: charged and plugged in, notifications off, the website running (4.3), the browser
      zoomed so the map is readable from the back of the room.
- [ ] Wi-Fi: join once and confirm the site loads. Keep a phone hotspot as a backup network.
- [ ] Clear leftover test rides on the phone if they would confuse the story.
- [ ] Open the Supabase dashboard in a second tab (SQL editor) for 4.4.
- [ ] Keep `vision/REPORT.md` open for the numbers on the last slide.

### 4.3 Running the website on the big screen

Pick one mode and stay in it.

**Fixtures mode (no network or project needed):**
1. `cd web && cp .env.example .env.local` and leave `NEXT_PUBLIC_DATA_SOURCE=fixtures`.
2. `npm run build && npm run start`, then open http://localhost:3000. A production build is
   steadier than `npm run dev` on stage.
3. Map tiles need internet. Offline, the route still draws on a blank background.
4. The page shows a "bundled sample data" banner. That is correct and should stay.

**Supabase mode (live shared rides):**
1. In `web/.env.local` set `NEXT_PUBLIC_DATA_SOURCE=supabase`, `NEXT_PUBLIC_SUPABASE_URL`, and
   `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Never put a secret or `service_role` key here.
2. These `NEXT_PUBLIC_` values are baked in when the site is built. Change them, then rebuild:
   `npm run build && npm run start`.
3. If the page shows a configuration message, one of the variables is missing or still a
   placeholder.
4. The page lists only rides with `share_publicly = true`. An empty page means nothing is
   shared yet.

### 4.4 Manually sharing a ride (when the app has no share toggle)

In the Supabase dashboard SQL editor (it runs with admin rights, so use it only on your own
project):

```sql
-- find the ride you just synced
select id, started_at, distance_m, share_publicly
from rides
order by started_at desc
limit 5;

-- share exactly one ride (replace the id)
update rides set share_publicly = true where id = '00000000-0000-0000-0000-000000000000';
```

Reload the website. After the demo, undo it:

```sql
update rides set share_publicly = false where share_publicly = true;
```

### 4.5 If something fails

| Symptom | Do this |
| ------- | ------- |
| No venue Wi-Fi | Phone hotspot for the laptop. If that fails, switch the site to fixtures mode (4.3) and say it is sample data. |
| Ride does not sync | Say the app is local-first and syncing is opt-in. Show the ride on the phone. Use 4.4 only if the ride reached the database; otherwise show fixtures mode and say so. |
| Website blank or error | Reload. Check `.env.local` and that you rebuilt after changing it. Fall back to fixtures mode. |
| Supabase project paused | Resume it in the dashboard (takes a minute) or fall back to fixtures mode. |
| Detector does not trigger | Skip that moment; the script works without it. Do not fake an alert. |
| Phone location is stuck | Walk a short loop outside if possible; otherwise play the saved ride in history. |
| Phone overheats or the app crashes | Switch to the second phone or to a short screen recording, and say it is a recording. |

Never fake a result live. If a feature is down, say it is down and show what does work.

### 4.6 After the demo

- [ ] Unshare rides (4.4 second query).
- [ ] Delete test rides from the database if they should not stay.
- [ ] Rotate any key that was ever pasted into chat, a screenshot, or a shared doc.
- [ ] Delete raw rear-camera clips unless everyone agreed to keep them
      (`vision/LABELING.md`, section 7).

## 5. Open items for this plan

- [ ] Fill in the slot length, presenter, and who runs the laptop.
- [ ] Decide fixtures vs Supabase mode for the big screen.
- [ ] Get the numbers and wording from B's `vision/REPORT.md`. Until it exists, the last slide
      says "we tried it on [N] clips" and nothing more.
- [ ] Rehearse twice, once with the network off.
