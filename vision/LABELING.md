# Whoosh Vision: Labeling Spec and Clip Protocol

Status: v1 draft. Written for task V1 in `.kiro/team/vision-subagent-tasks.md`. Read this
before anyone records or labels a clip. Change it only with the whole vision team's agreement,
and bump the version note at the bottom when you do, because labels made under different
rules cannot be mixed.

Detection in Whoosh is **experimental**. This document defines the ground truth we measure
against. It does not claim any detector meets it.

## 1. What counts as a positive event

The camera is on the bike, **facing backward**. A **positive event** (`label = approach`) is
a period in which:

1. a **motor vehicle** (car, truck, bus, motorcycle, or other motorized road vehicle) is
   behind the rider, **and**
2. it is **closing in** on the rider's lane or **passing close** to the rider.

"Closing in" means the vehicle is getting closer to the rider over time: its image grows
across consecutive frames, or it moves from the far field toward the rider's position.
"Passing" means it overtakes the rider on the same road.

### Time window

- `t_start_s`: the first moment the vehicle is **clearly visible and approaching**. "Clearly
  visible" means a labeler could say what kind of vehicle it is without guessing. Do not
  start the window at a speck on the horizon.
- `t_end_s`: the first moment **either** the vehicle has passed completely out of the frame
  (usually forward of the rider, past the image edge), **or** it stopped approaching (it
  slowed to match the rider's speed and holds a roughly constant distance, turned off, or
  stopped).
- Times are seconds from the start of the clip file, as a decimal (for example `12.4`).
  Label to the nearest 0.1 s. Frame-exact timing is not needed and is not realistic by eye.
- One vehicle produces one event. Two separate vehicles that overlap in time produce two
  rows with overlapping windows.

### Optional `close_pass` sub-flag

`close_pass` is `yes`, `no`, or empty (not judged). It marks events where the vehicle passed
the rider in a way the labeler judges to be **close**.

- It is a **human judgment** and it is **subjective**.
- **Distance cannot be measured from a single camera.** A monocular rear view gives no
  reliable meters. We deliberately do not define a numeric distance threshold, and nobody
  should invent one, estimate "3 feet" from the picture, or report one.
- The rule the labelers use: mark `yes` if, watching the clip, the vehicle passes noticeably
  close to the rider relative to the lane and shoulder available, for example it fills a
  large part of the image at the moment of passing, or it passes with little lateral gap
  visible. Mark `no` if the gap looks comfortable. If you cannot decide, leave it empty.
- Because it is subjective, report agreement between labelers on this flag separately
  (section 5) and do not use it for headline numbers unless agreement is reported next to it.

## 2. Negatives and ignore rules

These are **not** events. Do not write a row for them.

| Situation | Rule |
| --------- | ---- |
| Parked vehicles | Not an event. As the rider rides away from a parked car it shrinks in the image, and a car the rider is about to pass is in front, not behind. Neither is a vehicle approaching the rider. |
| Vehicles traveling away | Not an event. If it is moving away from the rider, it is not approaching. |
| Oncoming traffic on the other side of the road | Not an event, even when it is visible in the rear camera's wide view. It is not behind the rider in the rider's direction of travel. |
| Vehicle stopped at a light, behind the rider | Not an event while it is stopped. If it starts moving and then closes in on the rider, label from the moment it is clearly approaching. |
| Vehicle that stays far behind at a steady distance | Not an event (not closing in). |
| Bicycles, e-bikes, scooters, and pedestrians | Not events for the MVP. **This is a decision**, made to keep the first dataset simple and the claim narrow ("motor vehicles"). We may add a separate label later. |
| Vehicles on a different road, crossing, or turning away | Not an event unless it enters the rider's road behind the rider and approaches. |

If unsure whether something is an ignore case, use the tie-breaking rules in section 5.

## 3. Label file format

### 3.1 `events.csv` (required)

One CSV file **per recording session** (a session is one ride or one outing). It is named
`events.csv` and sits next to that session's clips, inside the git-ignored `data/` folder.

Columns, in this order:

| Column | Type | Allowed values / meaning |
| ------ | ---- | ------------------------ |
| `clip_id` | string | Matches `clip_id` in the manifest, for example `clip_0001`. |
| `t_start_s` | decimal | Start of the event, seconds from clip start. |
| `t_end_s` | decimal | End of the event, seconds from clip start. Must be greater than `t_start_s`. |
| `label` | string | `approach`. The column is extensible; new labels need an entry in this document first. |
| `side` | string | `left`, `center`, `right`, or `unknown`. See the direction rule below. |
| `vehicle_class` | string | `car`, `truck`, `bus`, `motorcycle`, or `other`. |
| `close_pass` | string | `yes`, `no`, or empty. See section 1. |
| `notes` | string | Free text. Avoid commas (or quote the field). Do not put names, plates, or addresses here. |

A clip with **no events** has no rows. List it in the manifest so it counts as negative
footage (needed for false alarms per hour).

### 3.2 Direction rule for `side`

`side` is from the **rider's perspective**, in terms of the rider's own left and right while
facing forward.

Because the camera faces **backward**, the image is turned around relative to the rider:

- **Rider's left = the RIGHT side of the video image.**
- **Rider's right = the LEFT side of the video image.**
- `center` = the middle part of the image, roughly the middle third horizontally.

This assumes the file is the unmirrored image from the phone's back camera (the normal case
for a saved recording). If a recording app shows or saves a mirrored image, check with the
slate (section 6) or a known landmark and note it in the manifest `notes`.

`side` is the side where the vehicle is **when it is first clearly visible and approaching**.
If it clearly changes sides during the event (for example it swings out to overtake), use the
side at `t_start_s` and describe the move in `notes`. Use `unknown` if you cannot tell.

**Heads-up for the detector code (V3/V4):** the app's `relativePositionHint` uses
`"left" | "center" | "right"`. Rules that compute it from box center x in image thirds must
map image-left to `"right"` and image-right to `"left"` if the hint is meant in the rider's
frame, or the team must explicitly document that the hint is in image coordinates. Decide this
once, in the contract, and make the evaluation use the same convention as `side` here.

### 3.3 Example

```csv
clip_id,t_start_s,t_end_s,label,side,vehicle_class,close_pass,notes
clip_0001,14.2,19.8,approach,left,car,no,"fake example: sedan overtakes with wide gap"
clip_0001,41.0,44.6,approach,center,truck,yes,"fake example: truck stays in lane then swings out"
clip_0002,8.5,12.1,approach,right,motorcycle,,"fake example: not judged for close pass"
```

(`left` in the first row means the vehicle was on the rider's left, which is the right side
of the video image.)

### 3.4 `boxes.jsonl` (optional)

For frame-level evaluation or training, an optional `boxes.jsonl` can sit next to
`events.csv`. It has **one JSON object per line**, one object per labeled box in one frame:

```json
{"clip_id": "clip_0001", "t_s": 15.0, "x": 0.62, "y": 0.41, "w": 0.18, "h": 0.22, "vehicle_class": "car"}
```

- `x`, `y`, `w`, `h` are **normalized** to the image size (0 to 1). `x`,`y` is the top-left
  corner of the box, and `w`,`h` are its width and height. Origin is the top-left of the
  image, as stored in the file (not rider-perspective).
- `t_s` is the time in seconds from clip start. Label sparse frames (for example every
  0.5 s inside an event). Boxes outside event windows are allowed and useful for tuning.
- Boxes are optional. Event-level evaluation needs only `events.csv`.

## 4. Variety and sample size

State this honestly in any report: **a small number of events gives anecdotal results.**

| Events labeled | What it supports |
| -------------- | ---------------- |
| Fewer than about 20 | "We tried it on N clips." Describe what happened. No rates, no percentages. |
| About 20 to 49 | Anecdotal. Counts such as "caught 14 of 18 events in our clips" are fine. Confidence intervals are wide: with a few dozen events, one more or fewer detection moves any percentage by several points, and the range around it is far wider than the headline number suggests. Report the counts and the sample, not a single polished percent. |
| 50 or more, across enough variety (target below) | Still a **small, one-bike, one-phone** sample. It supports "in our test of N events on these roads and conditions, the prototype detected X of N", with the sample described. It does not support general claims about other roads, phones, vehicles, or weather. |

**Hackathon target:** at least **50 events** across at least **3 different roads** and at
least **2 lighting conditions** (for example daylight and dusk). Also record some stretches
with no vehicles, so false alarms per hour can be measured. Rain or other weather is a bonus
if it can be done safely. If the team falls short, say so and report the smaller number.

Do not tune thresholds and report numbers on the same clips without saying so. If you can,
keep some clips aside that are never used for tuning.

## 5. Ambiguous cases and tie-breaking

Use these rules in order. Write the reasoning in `notes` when a rule decided it.

1. **Is it a vehicle behind the rider?** If you cannot tell what it is, skip it and do not
   guess a class. If it is a fully hidden or heavily occluded object, skip it.
2. **Is it approaching?** Judge from motion across the clip, not from a single frame. If it
   is not clearly closing in, it is not an event.
3. **Start time.** When unsure, pick the **later** time (the first moment you are confident
   the vehicle is approaching). A tight window is better than a speculative one.
4. **End time.** When unsure, pick the **earlier** of the candidate moments (when it left the
   frame or stopped approaching).
5. **Vehicle partly out of frame.** Still counts if it is clearly an approaching vehicle in
   the image. Use the side where most of it appears.
6. **Several vehicles in a convoy.** One event per vehicle if you can tell them apart. If the
   second vehicle is hidden behind the first until it pulls out, start its window when it is
   clearly visible.
7. **Vehicle slows and follows behind.** The event ends when it stops approaching. If it
   starts approaching again later, that is a new event.
8. **Motorcycle vs. bicycle at distance.** If you cannot tell, treat it as not a vehicle
   (bicycles are out of scope). Do not label `other` just to include it.
9. **Disagreement.** If the two labelers still disagree after rules 1 to 8, a third person
   decides, or the event is dropped and logged as "disputed" (count it, do not hide it).

### Two-labeler review and agreement

- At least **20% of events** (rounded up, picked at random, not the easy ones) must be
  labeled independently by a **second labeler**, without seeing the first labeler's rows.
- Record the result in the session's notes or in `REPORT.md`: how many events were
  double-labeled, how many the two labelers matched (same vehicle, overlapping windows), and
  how many time windows differ by more than 1.0 s. Report `side`, `vehicle_class`, and
  `close_pass` agreement separately. `close_pass` is expected to agree least.
- If agreement is low, fix this document first, then relabel. Do not hide low agreement.

## 6. Clip recording protocol

### Mount and orientation

- **Position:** mount the phone on the seat post or rear rack area, facing straight back,
  with a clear view of the road and no part of the rider or panniers filling the image. Aim
  the camera so the horizon is in the upper-middle of the image. It must be firm, with no
  wobble, and must not interfere with pedaling, braking, or the rider's view or balance.
- **Orientation:** the **back camera of the phone** faces backward. The saved image is not
  mirrored.
- **Portrait vs landscape:** record in **landscape**. Reason: vehicles approach and pass
  across the width of the lane, and landscape gives the wide view needed to see the side of
  the approach and to see vehicles earlier. Portrait is only acceptable if you cannot mount
  it any other way; note it in the manifest, and do not mix the two without recording it.
- Keep the **same mount and orientation for the whole session**. Changing them changes what
  "side" means in the image.

### Capture settings

- **Resolution and frame rate:** fixed **720p to 1080p at 30 fps**. Pick one per session and
  keep it. Reason: it is close to what an on-device detector will see, it keeps files and
  heat manageable, and fixed settings keep results comparable. Higher resolutions add heat
  and storage with no benefit for a model that downsizes the input anyway.
- Turn off any recording mode that changes frame rate or crops the image (cinematic mode,
  slow motion, aggressive stabilization). Note the mode used in the manifest.
- Lock exposure and focus if the app lets you, so the image does not hunt.

### Slate

At the start of each clip, record a **slate**: say aloud (or hold up, written on paper, with
no personal information) the **clip id**, for example "clip zero zero zero one". Do this
while stationary and safe. The slate lets the clip be matched to the manifest if filenames
get lost. If you use a written slate, make sure no faces or plates are in view.

### Clip length and logging

- Keep clips **30 to 120 seconds**. Shorter is easier to label and to delete; very long clips
  overheat the phone and are painful to review.
- For each clip, log in the manifest: date, **route type** (`location_type`, for example
  residential, arterial, bike lane, shared road), **lighting** (daylight, dusk, night),
  weather, mount, fps, resolution, who recorded it, and whether consent was noted.

### Battery and heat

- Video at 30 fps drains the battery and warms the phone, and a hot phone may throttle or
  stop. Start sessions with a charged phone, keep it out of direct sun when stationary, and
  stop recording if the phone shows a temperature warning. Note any thermal throttling in the
  manifest `notes`. This also feeds the on-device performance numbers later.

### Safety

- **Record only while riding safely.** Nothing here is worth a crash or a near miss.
- **Never touch or look at the phone while riding.** Start and stop recording while
  stopped, in a safe place off the road.
- **Obey all traffic laws.** Do not ride differently, ride slower, or take risks to
  "get" an event. Do not provoke drivers.
- **Prefer safer setups where possible:** have another person ride, or use a **stationary
  setup** (phone on a tripod well off the roadway, aimed at traffic approaching it, which
  approximates the rear view) to collect additional footage. Stationary footage differs from
  riding footage (no rider motion), so record it as such in the manifest `notes`. Never stand
  or set up in a traffic lane.
- Do not ask teammates acting as drivers to do anything unsafe. Staged passes happen on a
  closed or quiet road with the driver's agreement, at normal speeds, and in compliance with
  the law.

## 7. Privacy and consent

This follows `.kiro/steering/privacy.md`. Rear-facing footage records **bystanders, faces,
and license plates**, which are personal data.

- **Raw clips and frames stay off Git, off public buckets, and off shared links.** The
  repo `.gitignore` in `vision/` enforces this for common file types; do not rely on it
  alone.
- Share clips **only with teammates, on private storage**. Do not use "anyone with the link"
  sharing.
- **Delete raw clips after the hackathon** unless every team member agrees to keep them, and
  then store them privately with the same rules.
- **Consent:** get consent from any identifiable person who is **deliberately recorded**,
  such as a teammate acting as a driver or a friend riding nearby. Record that consent was
  noted in the manifest (`consent_noted`). Do not record or label anything where a
  participant has declined.
- **Never publish a frame, thumbnail, or screenshot with a readable plate or a face.** That
  includes slides, the README, the repo, social media, and the demo.
- **Do not show clips in the demo** without blurring faces and plates or having consent from
  everyone identifiable. When in doubt, show the detector's box overlay on a blurred frame or
  show numbers only.
- Label files (`events.csv`, `boxes.jsonl`) and real manifests can reference private clips,
  so they stay out of Git too. Commit only code, this document, and derived numbers.

## 8. What this data cannot tell us

- **Small sample.** Dozens of events, not thousands. Rates carry wide uncertainty.
- **One bike, one phone, one mount.** Results may not carry over to other phones, camera
  heights, or mounting angles.
- **Limited roads and times.** A few routes in one area. Other road layouts, traffic
  speeds, and vehicle types are not represented.
- **Limited weather.** Heavy rain, glare, fog, and night riding are likely under-represented
  or missing.
- **Subjective parts.** `close_pass` is a human judgment, and distance is not measured.
- **Not a safety test.** The data cannot show that an alert would prevent or predict a
  collision. It can only show how well a detector found vehicles we labeled as approaching.

---

Version: v1 (initial draft). Add a line here for each change to the rules.
