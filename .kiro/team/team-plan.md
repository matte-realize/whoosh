# Whoosh — Team Plan (3 people)

A hackathon-scoped split of Whoosh across three owners. The goal is **parallelism with a
working demo at every checkpoint**. The seams defined in the iOS spec (`HazardDetector`,
`AlertManager`, `HazardDetection`) are the contract that lets the three workstreams proceed
independently and integrate late.

## Roles

| Person | Role | Owns |
| ------ | ---- | ---- |
| **You** | iOS App | The native SwiftUI app: ride recording, GPS, map, persistence, UI, alert playback, and the integration seams. _Added:_ rear-camera capture, recording, ring buffer and clips, ride (screen-dim) mode, the frame-pipeline seam, and the watch/eyes-free seams. This is the demo surface. |
| **Teammate B** | Vision / Detection | On-device rear-camera vehicle detection: dataset, model, and the `HazardDetector` implementation that emits `HazardDetection` events. _Updated:_ the detector consumes frames as a `FrameConsumer` from iOS's frame pipeline (it never owns capture). |
| **Teammate C** | Backend / Data & Integration | The Supabase project (schema, Row Level Security, anonymous auth), the Whoosh website/dashboard that reads synced rides and near-misses, the shared data contracts, and dataset/eval tooling to unblock B. _Clarified:_ near-miss **events only**; never video, thumbnails, or clip references. |

### Role C (decided): Backend / Data & Integration on Supabase

C keeps the data contracts honest (so B's model output and your `HazardDetector` protocol
line up), owns the Supabase backend, and builds the website that shows synced rides and
near-misses on a big screen. C is never on the iOS critical path: the app is local-first and
the demo works in airplane mode. Supabase sync is an additive stretch (iOS tasks 26–28).

C's source of truth for the backend is `supabase-contract.md` in this folder. The iOS app
implements sync only after C marks it "Agreed."

## The integration contract (the one thing all three must agree on)

Everything hinges on a small, shared shape. It already lives in the iOS design as the seam:

```
HazardDetection {
    timestamp: Date
    kind: String                 // e.g. "vehicle" — open, not an enum yet
    confidence: Double           // 0...1
    relativePositionHint: String?  // "left" | "center" | "right" | nil
}

HazardDetector { onDetection callback; start(); stop() }
AlertManager   { fire(AlertKind) }   // iOS owns playback
```

Contract rules:
- Detector runs **on-device** and must **never block or slow ride recording**. _Update:_ a camera
  detector receives frames through the `FrameConsumer` seam (latest-wins, drops when busy); it does
  not own the capture session.
- iOS consumes `HazardDetection` events and decides whether/how to alert (debounce, cooldown).
- The same `HazardDetection` is what C logs as a near-miss (tied to the current route point).
- Agree on this shape first; freeze it before deep work. Changes go through a quick 3-way OK.

## Workstreams and checkpoints

Three checkpoints keep everyone converging on a demo.

### Checkpoint 1 — "It records" (foundation)
- **You:** iOS tasks 1–12 (project, theme, models, metrics, weekly stats, clock, repositories
  with deleteAll, location protocol + state machine, CoreLocation, formatters). A ride can be
  recorded and summarized in tests, and the design system is in place.
- **B:** Collect/borrow a small rear-facing driving/cycling dataset; stand up a notebook that
  runs a baseline detector on sample clips offline; measure rough precision/recall. **Make no
  reliability claims yet.**
- **C:** Freeze the `HazardDetection` contract with you and B. Create the Supabase project,
  finalize `supabase-contract.md` (tables, RLS, anonymous auth) and mark it "Agreed".
  Scaffold the website against a fixture JSON of rides.

### Checkpoint 2 — "It shows" (integration-ready)
- **You:** iOS tasks 13–21 (settings VM + screen, home + permissions/location-denied, home
  dashboard, map wrapper, active ride with hold-to-stop, summary, history, mid-ride
  persistence). End-to-end ride → summary → history works on device, with the Home dashboard
  and Settings in place.
- **B:** Package the model to run on-device (Core ML / Vision) behind a Swift type that
  conforms to `HazardDetector`; emit `HazardDetection` events from a live camera feed in a
  tiny standalone harness. Share a `.mlmodel`/package + the conforming class.
- **C:** Apply the schema and RLS policies; verify one anonymous user can't read another's
  rows. Website reads rides from Supabase (seeded test rows until the app syncs) and draws
  routes on a map; add a near-miss overlay driven by `HazardDetection` fixtures.
- **You (stretch, after task 23):** iOS tasks 26–28, opt-in sync into C's `rides` table.

### Checkpoint 3 — "It warns" (demo)
- **You:** iOS task 22 seams are real injection points; swap `NoopDetector` for B's detector
  and `StubAlertManager` for a real haptic/audio alert. Tasks 23–25 (composition, resilience,
  accessibility/privacy). Demo path: ride with rear camera → detection → haptic/audio alert,
  with honest "experimental" framing.
- **B:** Tune thresholds/cooldown with you; provide the measured performance numbers so copy
  stays honest.
- **C:** Live demo dashboard showing the ride + logged near-misses; owns the demo script and
  pitch; final polish.

## Dependency map

```
            freeze HazardDetection contract (all 3)  ── Checkpoint 1
                     │
   You: app core ────┼──── B: offline baseline ──── C: demo scaffold / contract
                     │
   You: UI + persist ┼── B: on-device HazardDetector ── C: demo renders real data  ── Checkpoint 2
                     │
   You: inject B+real alerts ── B: tune + numbers ── C: dashboard + pitch           ── Checkpoint 3
```

Critical path: the **contract freeze** at Checkpoint 1. After that, the three streams only
reconverge at integration, so blockers are minimized.

## Interfaces & ownership boundaries

- **iOS ↔ Vision:** the `HazardDetector`/`HazardDetection` Swift types. B delivers a type
  conforming to `HazardDetector`; you own injection, debouncing, and `AlertManager` playback.
  You never depend on B's internals; B never imports your app code.
- **iOS ↔ Backend:** Supabase, defined by `supabase-contract.md`. The app is local-first;
  sync is opt-in, behind `RideSyncService`, and uses only the anon key + RLS. C owns the schema
  and policies; you own the client. It must never become a demo dependency.
- **Vision ↔ Backend:** C provides dataset storage and eval tooling; B provides detections and
  measured performance. Keep training data off any public bucket.

## Crash response workstreams (post-MVP, opt-in — new)

Spec: `.kiro/specs/crash-response/` (requirements, design, tasks). Backend contract:
`crash-alert-contract.md` (DRAFT, owned by Role C). Nothing here is part of the MVP demo scope or
changes the three MVP checkpoints; it is a fourth, optional checkpoint after "It warns". **No
code is written until the iOS owner approves the spec and Role C marks the contract Agreed.**

| Workstream | Owner | Scope | Spec tasks |
| ---------- | ----- | ----- | ---------- |
| iOS crash response | **You (iOS)** | Models, pure message builder and state machine, contact store (Keychain), consent, connectivity, notifier protocol + fakes, coordinator, countdown/status/log/setup screens, Supabase client implementation, privacy-script update, integration with `RideSessionViewModel`, Simulate-crash demo path, QA checklist | `crash-response/tasks.md` 0–29 |
| Backend SMS alerts | **Role C** | Edge Functions `send-crash-alert`, `crash-alert-status`, `sms-status-callback`, `delete-crash-audit`; provider trial setup and limits; audit tables + RLS + retention; cost caps and kill switch; contract tests; contract finalization | `crash-response/tasks.md` C1–C12 |
| Crash detector (optional) | **Teammate B** (or the iOS owner) | Experimental Core Motion heuristic behind the `CrashDetector` seam, field testing with measured false-positive numbers. The camera-side `FootageBuffer` is now delivered by the iOS owner in the rear-camera spec (task 30 there). | `crash-response/tasks.md` 32–33 (34 superseded by `rear-camera/tasks.md` 30) |

### Checkpoint 4 — "It alerts" (optional, after Checkpoint 3)

- **You:** crash-response iOS tasks, **Tier 0 first** (Simulate crash → countdown → cancel/expire →
  composer fallback, works in airplane mode), then Tier 1 when the backend is ready.
- **Role C:** contract Agreed → provider trial account → migrations/RLS → `send-crash-alert` →
  status callback/status endpoints → caps and kill switch → staging + rehearsed kill switch.
- **B (optional):** pure signal core for the motion heuristic, then device field-testing. Nothing
  about detection reliability is claimed until measured.
- **Demo tiers:** Tier 0 (iOS only) must never depend on the backend; Tier 1 adds a real trial SMS
  to a verified teammate phone ("WHOOSH DEMO - NOT REAL"). If the provider fails, show Tier 0.

### New interfaces

- **iOS ↔ Backend:** `crash-alert-contract.md` (anonymous Supabase JWT, fixed templates, idempotent
  by `crashEventId`). No provider credentials in the app or the repo; the backend stores no
  plaintext numbers, message bodies, or coordinates.
- **iOS ↔ Detector:** the `CrashDetector` protocol (probable-crash signal with timestamp,
  confidence, source). B never imports app code; the iOS owner owns arming, countdown, and alerts.
  Camera-assisted cues could later arrive behind the same protocol.
- **Shared test data:** Appendix A of the contract (golden messages) is the single source of truth
  for the iOS message builder tests and the backend renderer tests.

## Rear-mounted camera workstreams (new — October 24, 2026)

Spec: `.kiro/specs/rear-camera/` (requirements, design, tasks; **draft, awaiting owner approval**).
Owner context: the phone clips onto a holder on the back of the seat and records the cars behind;
recording can ship now, before the vision model. This **changes the split** and adds a seam
between iOS and Vision. No code is written until the owner approves the spec.

| Workstream | Owner | Scope | Spec tasks |
| ---------- | ----- | ----- | ---------- |
| Capture, recording, clips | **You (iOS)** | `CameraCaptureService`, rolling-segment recorder, ring buffer, clip pinning/viewing/deleting/export, Mount & frame, ride mode (screen-dim, touch lock), permission and settings, background location, interruption handling, device QA and budgets | `rear-camera/tasks.md` 1–32 |
| Frame-pipeline seam | **You (iOS)** | `FrameConsumer` / `VideoFrame` / `FramePipeline` with a latest-wins, never-blocking backpressure rule; `FakeCameraSource`; updated `HazardDetector` contract | tasks 6, 11, 14, 35 |
| Watch / eyes-free seams | **You (iOS)** | `RideStatus`, `RideRemoteControl`, `AlertSink` fan-out, audio sinks; the Apple Watch companion itself is specified in `.kiro/specs/watch-companion/` (open decision O-CAM1; see "Apple Watch companion workstreams" below) | tasks 13, 29, 34 |
| Vision model + detector | **Teammate B** | A `HazardDetector` that is also a `FrameConsumer` (reads frames from the pipeline; never owns capture, permission, or recording); offline evaluation on real mounted footage; measured thresholds for the near-miss policy | B1–B3 |
| Near-miss events in the database | **Role C** | Confirm `near_misses` takes **events only (no video, no clip id, no thumbnail)**; later, website markers | C-R1, C-R2 |

### Interfaces and ownership boundaries (additions)

- **iOS ↔ Vision (changed):** the `HazardDetection` value type is **unchanged and still frozen**.
  What is new is *how a detector gets input*: B implements `FrameConsumer` and receives `VideoFrame`s
  (pixel buffer, timestamp, orientation) off the main actor. B never imports app code beyond these
  types, never creates an `AVCaptureSession`, and never requests camera permission. The consumer
  contract and backpressure rule get the same **3-way OK freeze** as `HazardDetection` (rear-camera
  task 11) — B can start the moment that merges and test against `FakeCameraSource`.
- **iOS ↔ Backend:** footage never crosses this boundary. Near-miss uploads (later) carry the
  contract fields only. The `near_misses` contract is unchanged; Role C confirms there is no video
  or clip reference column (C-R1).
- **Vision ↔ Backend:** unchanged. Real mounted-footage clips recorded by the app (never uploaded
  automatically) are a better evaluation set for B than borrowed dashcam data; sharing any clip with
  B or C is a deliberate, manual act by the rider who owns it.

### Checkpoint 2.5 — "It records" for the camera (inserted before Checkpoint 3)

- **You:** rear-camera Tier 0 (record → Mount & frame → ride mode → save clip → view/delete clip),
  background GPS, device QA of heat/battery/storage budgets.
- **B:** `FrameConsumer` adapter (B1) against `FakeCameraSource`; start collecting real mounted
  footage once the recorder runs on a device.
- **C:** confirm the `near_misses` fields; nothing else is required.
- **Demo-mode coordination:** the parallel `demo-mode` spec's simulated detections flow through the
  same near-miss/pinning path so a demo can show clips without a bike.

### Camera risks added to the risk register

See the rows below ("Heat on a seat post in sun", "Vibration blur", "Rain", "Battery drain", "Storage",
"Silent camera failure", "Hidden-recording perception", "Watch dependency").

## Apple Watch companion workstreams (new — October 24, 2026)

Spec: `.kiro/specs/watch-companion/` (requirements, design, tasks; **draft, awaiting owner approval**).
With the phone on the seat post, the wrist is the only in-ride surface, so this spec adds a watchOS app
(controls, live status, wrist haptics, crash-countdown cancel) and a pre-ride "watch connected, haptics
test" screen on the phone. It builds on the rear-camera seams (`RideStatus`, `RideRemoteControl`,
`AlertSink` fan-out) and the crash-response countdown. No code is written until the owner approves the
spec **and a feasibility spike on the owner's Apple Watch SE returns a go decision** (its central bet, a
cycling workout session that keeps the watch app reachable and haptic-capable with the wrist down, is
documented by Apple but unmeasured here). The Garmin fenix 6x and the Whoop are out of scope.

| Workstream | Owner | Scope | Spec tasks |
| ---------- | ----- | ----- | ---------- |
| Feasibility spike, project setup, adapters, device QA | **You (iOS)** + the owner's watch | Run and extend `spikes/watch-haptics/` in a new folder; add the watch target and the shared `Packages/WhooshWire` package; WatchConnectivity adapters; workout-session keep-alive; battery and latency measurements | `watch-companion/tasks.md` 0–3, 16–19, 28 |
| Pure core and phone seams | **You (iOS)** (a second contributor can take the package) | Versioned wire codec, command reducer and dedupe, arming, haptic catalog/limiter/freshness, routing and escalation, loopback tests | tasks 4–15 |
| Watch UI, readiness screen, crash cancel, start from wrist, notices | **You (iOS)** | Ride/Controls/Idle/Summary pages, phone Apple Watch screen, countdown takeover, reconnect handling, accessibility, privacy and App Review pass | tasks 20–27, 29 |
| Spike support | **Role C** | Author of the spike: share notes and help interpret the test protocol; no schema, API, or database change is needed (the watch sends nothing to the database) | C-W1 |
| Vision / detector | **Teammate B** | No tasks. The wrist cue is driven by the same `HazardDetection` through the existing gate, cooldowns, and fan-out. | — |

### Interfaces and ownership boundaries (additions)

- **iOS ↔ Watch:** a versioned wire contract over WatchConnectivity, defined once in a Foundation-only
  package both apps compile. The phone is authoritative; the watch sends typed, idempotent commands and
  never decides a ride, camera, or crash state. Commands and alerts are never queued for later delivery.
- **Watch ↔ everything else:** nothing leaves the rider's own devices. The watch receives no coordinates,
  routes, video, contact names or numbers; the crash countdown shows a contact count only. The watch app
  makes no network requests.
- **Detector → wrist:** unchanged `HazardDetection`; gate, cooldowns, and fan-out are layered (the
  rear-vehicle gate, the phone sink's 2 s cooldown, the routing policy's 3 s cooldown, the watch limiter).

### Checkpoint 2.75 — "It buzzes" (after the camera checkpoint)

- **You:** spike go decision, then Tier 0 (readiness screen, haptics test, pattern preview, demo-mode forced
  alert buzzing the wrist), then Tier 1 (a ride controlled from the wrist).
- **Role C:** optional notes on the spike; nothing else.
- **Demo fallback:** if the watch misbehaves, the phone's audio path and the ride itself are unaffected.

## Risk register (team-level)

| Risk | Owner | Mitigation |
| ---- | ----- | ---------- |
| Detection not reliable by demo | B + You | Frame as experimental; demo works without warnings as fallback (ride recording alone). |
| Contract churn breaks integration | All | Freeze `HazardDetection` at Checkpoint 1; changes need 3-way OK. |
| Camera/GPS battery drain in demo | You + B | Keep camera optional; GPS accuracy tunable; charged devices; short demo ride. |
| Scope creep (near-miss, routing) | All | Those are post-MVP; see product steering "NOT in MVP". |
| Backend becomes a blocker | C | App never hard-depends on cloud; cloud is additive only. |
| Overclaiming safety in the pitch | C + You | Honest copy rule from privacy steering applies to the pitch too. |
| Crash alerts overclaim ("we detect crashes / help is coming") | All | Experimental framing; "not a guaranteed emergency-response service" in setup, consent, countdown, status, and the pitch; privacy script flags claims. |
| False crash alerts annoy contacts | You + B | Countdown with one-tap cancel, suppression window, per-ride cap, detector off by default, measure before enabling. |
| SMS provider trial limits / registration lead time | C | Trial route with verified numbers for the demo; 10DLC/toll-free registration is production work; Tier 0 fallback demo. |
| SMS cost or abuse (anonymous accounts are cheap) | C | Fixed templates, per-user and per-recipient caps, spend cap, kill switch (rehearsed), App Attest later. |
| Safety feature depends on the cloud | You + C | Opt-in and labeled non-guaranteed; queue + composer fallback; core ride recording unaffected. |
| Foreground-only limits (app closed/suspended) | You | Documented in consent; time-sensitive local notification backup; server-side countdown is a v2 option. |
| Message text drifts between iOS and backend | You + C | Shared golden cases (contract Appendix A) and `templateVersion`. |
| Accidental real 911 call during the demo | You | Call 911 is manual-only and hidden for drills. |
| Time pressure on a post-MVP feature | All | Tier 0 first; stretch items (motion detector, all-clear) never block. |
| **Heat on a seat post in sun** (dark phone, direct sun, charging) | You | Thermal policy (reduce frame rate/resolution, then stop the camera; GPS continues), dim ride mode, mount tips (light case, shade, don't charge in heat), measured in rear-camera task 31. Detection load also counts toward heat. |
| **Vibration blur and rolling shutter** | You + B | Stabilization where supported, bounded exposure, field test on a real mount; B evaluates on blurry real footage. |
| **Rain and lens droplets** | You | Touch lock in ride mode, lens-wipe reminder, no waterproof claim, honest copy; detector confidence suffers — B reports it. |
| **Battery drain (camera + GPS + display)** | You + B | Dim OLED ride mode, Efficient/Reduced profiles, camera stops before GPS at low battery, power-bank guidance, budgets measured; B reports inference cost. |
| **Storage** | You | Bounded ring buffer and clip cap, free-space guard, ring cleared at ride end, short default retention. |
| **Silent camera failure** (the rider cannot see the screen) | You | Every stop/degrade announced on watch/audio, red-to-amber dot, summary note; no silent states. |
| **Hidden-recording perception / other people in footage** | You | Red dot always on, system indicators untouched, local-only footage, short retention, easy deletion, informational copy about local laws. |
| **Watch dependency unknown** (reachability, latency, owner has a watch?) | You | Seams + audio fallback now; the watch spec (`watch-companion`) starts with a feasibility spike (O-CAM1). |
| **Watch keep-alive bet unproven** (cycling workout session may not keep haptics/reachability with the wrist down on the owner's SE) | You | Spike first (`watch-companion` task 1) with a fallback ladder down to phone audio; no claim of wrist alerts before it passes. |
| **Watch battery drain on a long ride** (older SE) | You | Measure, show watch battery before the ride, display-aware status, end the session at 5%; no battery claim before measured. |
| **Haptic not felt or muted** (sleeve, vibration, Silent/Theater mode, Water Lock) | You | Distinct patterns tuned on the wrist, haptics test before the ride, audio escalation when the watch does not confirm, honest "cannot guarantee" copy. |
| **Wrist cancel misread** (rider thinks a crash alert was cancelled when it was sent) | You | Reply-confirmed outcomes only ("Too late — alert is sending" shown honestly); the phone keeps its audible countdown and its own cancel. |
| **iOS interrupts the camera when the phone locks** | You | Ride mode keeps the app foreground; on lock the camera stops cleanly, the rider is told, GPS continues via the `location` mode (O-CAM2). |
| **Crash-countdown cancel unreachable on a rear mount** | You | Ride mode exits to full brightness and speaks the countdown; cancel on the watch (`cancelCrashCountdown`); consent copy says what is needed without a watch. |

## What is explicitly NOT in the hackathon MVP

Routing/directions, safer-route recommendations, infrastructure analysis, accounts/auth, and any
claim that the app reliably predicts or prevents collisions. (_Update:_ rear-mounted camera
recording, the `location` background mode, and the Apple Watch companion are now specified or
recommended in `.kiro/specs/rear-camera/` and `.kiro/specs/watch-companion/` and are no longer in this list; they remain post-MVP and
opt-in.) These are future; keep them out of the demo scope. Emergency contacts and
crash alerts are a separate **post-MVP opt-in feature** (see "Crash response workstreams" above).

## First actions (today)

- **All three:** 30-minute sync to freeze the `HazardDetection` contract and review the draft
  `supabase-contract.md`.
- **You:** start iOS task 1 (scaffold) once the spec is approved. For the camera feature, review
  `.kiro/specs/rear-camera/` and answer O-CAM1…O-CAM6.
- **B:** gather a handful of sample rear-camera clips and run a baseline.
- **C:** create the Supabase project, share the URL + anon key privately (not in Git), and
  scaffold the website against a fixture ride JSON.
