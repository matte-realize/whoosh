# Requirements — Whoosh Demo Mode

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O-DM1–O-DM8 (`design.md`, "Owner resolution"). This spec adds an **opt-in developer/demo mode**
so the whole app can be shown — recording, the live map, metrics, the signal-lost banner, the
rear-vehicle alert, and the crash-response countdown — **while standing still indoors, with no
bike, no real GPS movement, and no real crash**. It produces documents only; no Swift code is
written until the owner approves requirements, design, and tasks.

## Introduction

Whoosh is a cycling-safety app whose best features only appear while actually riding: GPS
movement drives the map and metrics, rear-vehicle alerts are meant to fire only while moving,
and crash alerts require a crash. None of that is demonstrable on a desk in a conference room.
**Demo mode** is a single, off-by-default toggle in Settings that, when on, unlocks a small set
of **demo tools** that drive the app's *real* code paths with *simulated* inputs:

- a **simulated ride** that plays a scripted Boston route through the existing
  `LocationTracking` seam, so recording, the live map, the three metrics, pause/resume, the
  signal-lost banner, hold-to-stop, the summary, and history can all be shown standing still;
- a **rear-vehicle alert demo** that fires the real `AlertManager` path (haptics + audio +
  visual banner) on demand, bypassing the normal "only while moving" gate;
- a **crash drill** that runs the real `CrashResponseCoordinator` with the `drill` template
  ("DEMO — NOT REAL"), hiding Call 911 and never consuming the real-alert cap;
- **seed sample data** so Home, History, and summaries look populated for screenshots;
- **permission/state previews** (location-denied, signal-lost, storage-unavailable, crash
  countdown/status) without changing real permissions.

It builds on the finished ride-recording MVP (`../ride-recording-mvp/`, tasks 1–27 implemented)
and the approved crash-response spec (`../crash-response/`, Tier 0 starting in parallel). It
reuses their seams: `LocationTracking` + `FakeLocationTracker`, `HazardDetector`/`NoopDetector`,
`AlertManager`/`StubAlertManager`, `RideSessionViewModel`, `SettingsViewModel`, `AppEnvironment`,
and (from crash-response) `CrashDetector` + `DebugCrashSimulator` + `CrashResponseCoordinator`.

### Design intent and non-negotiables

- **Zero behavior change when off.** With demo mode off the app behaves exactly as it does
  today; every existing test passes unchanged. Demo mode is the *only* thing that can change
  behavior, and it is off by default.
- **Impossible to trigger accidentally in normal mode.** Simulated rides, forced alerts, and
  drills are reachable only while demo mode is on, behind its tools panel.
- **Never fakes a real alert.** Demo mode never sends a real (non-drill) crash alert, never
  dials, and never uploads demo data. Drills always use the `drill` template.
- **Unmissable labeling.** While demo mode is on, an unmistakable "DEMO MODE" badge (icon +
  text, never colour alone) is visible on Home, the ride screen, and the emergency/countdown
  screens, so no one — including the rider — mistakes simulated output for real data.
- **Honesty rules still apply.** All copy obeys `scripts/privacy-check.sh` and the honesty rules
  in `privacy.md`/`product.md`; demo mode does not weaken any privacy invariant.

### Explicit non-goals

- Demo mode is **not** a cheat/QA automation harness; it exposes a few operator-driven tools,
  not a scripting API.
- It does **not** add any new real sensor, detector, or network path. The experimental motion
  crash detector and the real backend SMS path are owned by the crash-response spec.
- It does **not** change the normal-mode rear-alert policy except to *define* it (see
  Requirement 4) so that the demo's "bypass the stationary gate" behavior is well-specified.
- Non-US regions, additional scripted routes beyond one good Boston loop, and a public/App-Store
  consumer "demo" are out of scope (the audience is the team and hackathon judges).

## How to read this document

- Acceptance criteria use EARS-style phrasing (WHEN/WHILE/IF ... THEN ... SHALL ...) so each is
  individually verifiable.
- **Priority** tags: `Demo-critical` (must work for the live demo), `Important` (strongly
  expected), `Future-seam` (defined now, built later).
- "Configurable" means the value lives in one `DemoTuning` constants type with a documented
  default; it does not mandate a user-facing control.
- Cross-spec references use "MVP task N" (`../ride-recording-mvp/tasks.md`) and
  "Crash task N" / "Crash Req N" (`../crash-response/`).
- Open decisions for the owner are tagged **O-DM1**, **O-DM2**, … and summarized at the end.

## Glossary

- **Demo mode** — the off-by-default state, toggled in Settings, that unlocks the demo tools and
  shows the "DEMO MODE" badge everywhere.
- **Demo tools** — the operator-facing panel (in Settings, and a compact floating menu on the
  ride screen) that triggers the simulated ride, forced alert, crash drill, seed/clear data, and
  state previews.
- **Simulated ride** — a ride recorded from a scripted route played through `LocationTracking`
  instead of real GPS. Flagged as a **demo ride** in storage.
- **Demo ride** — any ride created while demo mode produced its points; `isDemo == true`.
  Excluded from sync; excluded from weekly stats per O-DM2.
- **Scripted route** — a bundled, timestamped sequence of route points (coordinates, speeds,
  accuracies) describing a realistic Boston loop, including a pause segment and a signal-loss
  gap.
- **Forced rear-vehicle alert** — a demo-only invocation of the real `AlertManager.fire` path,
  bypassing the normal stationary gate.
- **Stationary gate** — the normal-mode rule that suppresses rear-vehicle alerts unless a ride
  is recording and speed exceeds a configurable threshold (so a resting rider isn't buzzed).
- **Crash drill** — a simulated crash routed through the real `CrashResponseCoordinator` using
  the `drill` template; Call 911 hidden; real-alert cap untouched (Crash Req 5.3, 19.9).
- **DEMO MODE badge** — the persistent, unmissable icon-plus-text indicator shown while demo
  mode is on.

---

## Requirement 1: The Demo mode toggle

**Priority:** Demo-critical

**User story:** As the person demoing Whoosh, I want one clear switch that turns the whole demo
experience on and off, so I can prepare on stage and never leave it on by accident.

### Acceptance Criteria

1. Settings SHALL contain a dedicated **"Demo mode"** section, separate from the other Settings
   rows, with a single toggle that is **OFF by default** and a plain-language explanation of
   what demo mode does (shows simulated rides/alerts for demonstrations; nothing is real;
   nothing is uploaded).
2. The toggle state SHALL be persisted in `UserDefaults` and SHALL survive app relaunch.
3. WHEN the rider enables demo mode THEN the app MAY show a brief confirmation ("Turn on Demo
   mode? Rides and alerts shown will be simulated, labelled DEMO, and never sent or uploaded.")
   before enabling (O-DM4 decides whether the confirmation is required or optional).
4. WHEN demo mode is enabled THEN the demo tools (Requirement 3) SHALL become reachable and the
   DEMO MODE badge (Requirement 2) SHALL appear; WHEN it is disabled THEN the tools SHALL become
   unreachable and the badge SHALL disappear **immediately**, restoring normal behavior with no
   relaunch.
5. WHILE demo mode is OFF THE app SHALL behave exactly as it does without this feature: no demo
   tools, no badge, no simulated services wired in, and no change to any existing behavior or
   test (Requirement 9.1).
6. IF a simulated ride, a crash drill, or a queued demo action is in progress WHEN demo mode is
   turned off THEN the app SHALL end/cancel it safely (stop the simulated ride as if stopped,
   cancel a drill countdown as a rider cancel) and SHALL NOT leave a half-simulated state or
   send anything.
7. The toggle and its explanation SHALL use the design system and convey state with icon + text,
   not colour alone (MVP Req 15, 10.5).

## Requirement 2: Unmissable demo labelling

**Priority:** Demo-critical

**User story:** As anyone looking at the screen, I want it to be obvious that what I'm seeing is
a demonstration, so I never mistake a simulated ride or a drill for real data.

### Acceptance Criteria

1. WHILE demo mode is on THE app SHALL show a persistent **"DEMO MODE"** badge (icon + text) on
   the Home screen, the active-ride screen, and every emergency/crash screen (setup, countdown,
   status), positioned so it does not obscure primary ride metrics or the "I'm OK — Cancel"
   control.
2. The badge SHALL convey its meaning with **icon + text**, never colour alone, and SHALL meet
   the app's contrast and Dynamic Type expectations (MVP Req 10.5, Crash Req 18).
3. WHILE demo mode is on AND a demo ride is being recorded or shown THE active-ride screen and
   the summary/history rows for that ride SHALL additionally indicate the ride is simulated
   (for example a "Demo ride" tag), so a demo ride is never confused with a real one.
4. The crash **drill** countdown and status screens SHALL show the drill labelling required by
   the crash-response spec ("DEMO — NOT REAL", Call 911 hidden) **in addition** to the DEMO MODE
   badge (Crash Req 17.3, 19.9); the two labels SHALL be consistent and non-contradictory.
5. The badge SHALL NOT itself be interactive in a way that could be mistaken for a control; the
   demo tools are reached through Settings and the ride-screen demo menu (Requirement 3), not by
   tapping the badge (tapping MAY open the demo tools as a convenience — O-DM5).
6. WHEN demo mode is turned off THEN every DEMO MODE badge and demo-ride tag for the *live* UI
   SHALL disappear immediately (stored demo rides keep their persistent "Demo ride" tag per
   Requirement 5).

## Requirement 3: Demo tools panel and ride-screen demo menu

**Priority:** Demo-critical

**User story:** As the presenter, I want all the demo triggers in one obvious place — and a
quick version on the ride screen — so I can run the demo smoothly without digging.

### Acceptance Criteria

1. WHILE demo mode is on THE Settings "Demo mode" section SHALL present a **demo tools** panel
   offering: Start/stop a simulated ride (Requirement 5); Simulate approaching vehicle
   (Requirement 4); Simulate crash / crash drill (Requirement 6); Seed sample data and Remove
   demo data (Requirement 7); and State previews (Requirement 8).
2. WHILE demo mode is on THE active-ride screen SHALL present a **compact floating demo menu**
   (a small, clearly-labelled control that does not obscure the three metrics or the hold-to-
   stop button) offering at least: Simulate approaching vehicle, Simulate crash (drill), and
   toggle/adjust the simulated-ride playback speed (Requirement 5.6).
3. The demo tools SHALL be reachable **only** while demo mode is on; WHILE demo mode is off the
   tools and the ride-screen demo menu SHALL NOT exist in the view hierarchy (Requirement 9.2).
4. Each demo action SHALL be clearly labelled as a demonstration and SHALL use honest,
   experimental copy consistent with `privacy.md` (no claim of reliable detection or delivery).
5. The demo tools and the floating menu SHALL be operable one-handed with ≥ 60 pt targets and
   SHALL be VoiceOver-labelled (MVP Req 10.3, 10.6).
6. The floating demo menu SHALL be dismissible/collapsible so it never blocks the "I'm OK —
   Cancel" takeover or hold-to-stop; WHILE a crash countdown takeover is up THE floating menu
   SHALL be hidden behind it (Crash Req 8.8).

## Requirement 4: Normal-mode rear-alert gate, and the forced-alert demo

**Priority:** Demo-critical

**User story:** As a resting rider I don't want the rear-vehicle alert buzzing while I'm stopped;
as a presenter I need to show that alert on demand while standing still.

### Acceptance Criteria

1. The system SHALL define the **normal-mode rear-vehicle alert gate** as a pure, unit-tested
   rule: a rear-vehicle alert from the detector SHALL be delivered to `AlertManager` **only
   while** a ride is in `recording` (not `paused`, `signalLost`, `idle`, or `finished`) **and**
   the rider's current speed exceeds a configurable threshold (default **2 m/s**, ~4.5 mph) so a
   stationary or resting rider is not alerted.
2. WHILE the rider is stationary or resting in **normal mode** THE system SHALL suppress
   rear-vehicle alerts per criterion 1 (the gate "closes").
3. WHILE demo mode is on THE **forced rear-vehicle alert** demo action SHALL fire the **real**
   `AlertManager.fire(.cautionRearVehicle)` path — producing haptics, a short audio tone, and a
   visual banner — **bypassing the stationary gate only** (it works while stationary and even
   without an active ride). It SHALL NOT bypass any other safety rule and SHALL NOT fabricate a
   `HazardDetection` that could be logged as a real detection.
4. The forced-alert demo SHALL offer an **auto-trigger every N seconds** option (configurable
   default, e.g. every 10 s) that can be started and stopped from the demo tools or the ride-
   screen demo menu; turning demo mode off SHALL stop the auto-trigger.
5. The visual banner and any copy SHALL be framed as an **experimental** cue and SHALL NOT claim
   the app predicts or prevents collisions (MVP Req 9.3; `privacy.md` honesty rules).
6. The demo-only bypass SHALL be impossible to reach in normal mode: WHILE demo mode is off THE
   only path to `AlertManager.fire` SHALL be the gated normal path of criterion 1
   (Requirement 9.2).
7. Delivering a real haptic + audio alert requires a real `AlertManager` implementation to exist
   (today only `StubAlertManager` ships). This spec SHALL task a real
   `HapticAudioAlertManager` behind the existing `AlertManager` protocol (Core Haptics /
   `UIFeedbackGenerator` + a short tone via `AVAudioSession`), keeping the protocol unchanged and
   the normal (gated) behavior intact.

## Requirement 5: Simulated ride

**Priority:** Demo-critical

**User story:** As a presenter standing indoors, I want to play back a realistic ride so judges
see the map draw, the metrics climb, pause/resume, the signal-lost banner, hold-to-stop, and the
summary — all without moving.

### Acceptance Criteria

1. WHILE demo mode is on AND the rider starts a **simulated ride** THEN the app SHALL record a
   normal ride whose location updates come from a **scripted route** played through the existing
   `LocationTracking` seam (a `SimulatedRouteTracker`, or `FakeLocationTracker` driven by a
   player), so `RideSessionViewModel` and every downstream screen behave exactly as with real
   GPS.
2. The scripted route SHALL be a **realistic Boston loop** (e.g. along the Charles River / Mass
   Ave) with per-point timestamps, plausible speeds, and horizontal accuracies, and SHALL
   include at least one **pause segment** and one **short signal-loss gap** so the paused state
   and the amber signal-lost banner both appear during the demo.
3. The simulated ride SHALL support playback at **1×** and at least one **accelerated** speed
   (e.g. 4× or 10×, configurable) so a multi-minute route can be shown in under a minute;
   changing speed SHALL NOT corrupt distance, duration, or the active-duration accounting (the
   scripted timestamps, scaled by the speed factor through the injected `Clock`, drive the ride).
4. A simulated ride SHALL **never mix with real GPS** in the same ride: while a simulated ride
   is active the app SHALL NOT also feed real `CLLocationManager` updates into that ride, and a
   real ride SHALL NOT accept scripted points.
5. A finished simulated ride SHALL be persisted as a **demo ride** (`isDemo == true`) and SHALL
   be visibly flagged as simulated in History (Requirement 2.3). Demo rides SHALL be **excluded
   from sync** (Requirement 9.3 / MVP Req 12) and, per **O-DM2**, **excluded from weekly stats**
   unless the owner decides otherwise.
6. The simulated ride SHALL be controllable from the demo tools and the ride-screen demo menu:
   start, pause/resume (either via the normal ride controls or the menu), change speed, and stop
   (the normal hold-to-stop finalizes it like any ride).
7. WHEN demo mode is turned off WHILE a simulated ride is active THEN the app SHALL stop the
   simulated ride cleanly (finalize or discard per O-DM6) and SHALL NOT leave the tracker
   emitting scripted points.
8. The simulated ride's scripted route, speeds, pause segment, and signal-loss gap SHALL come
   from a **pure, Foundation-only** route source that is unit-testable without a device, and the
   player's point-timing SHALL be driven by the injected `Clock` so tests are deterministic.

## Requirement 6: Crash drill (global demo)

**Priority:** Demo-critical

**User story:** As a presenter, I want to show the full crash-response countdown and alert flow
on stage without a crash and without risking a real text or a real 911 call.

### Acceptance Criteria

1. WHILE demo mode is on THE demo tools and the ride-screen demo menu SHALL offer **Simulate
   crash**, which injects a drill signal through the **real** `CrashResponseCoordinator` via the
   crash-response `DebugCrashSimulator` (Crash Req 5.3), producing the real full-screen
   countdown, feedback, and (on expiry) the real notifier path with the **`drill`** template
   ("WHOOSH DEMO - NOT REAL", Crash Req 10.7).
2. The drill SHALL **hide the "Call 911" control** (replaced by an inert "Demo" label, Crash Req
   17.3) and SHALL **not consume the real-alert per-ride cap** (Crash Req 6.6, 19.9).
3. The drill SHALL work **while stationary and without an active ride**: demo mode SHALL bypass
   the crash-detector **arming gate** (Crash Req 5.4 / O10) **for drills only**, so a drill can
   be shown from Home or a simulated ride; it SHALL NOT arm the real detector or change the
   normal arming rule.
4. The crash-response feature's own consent and reachable-contact rules SHALL still apply to what
   a drill actually *sends*: if no backend/contact is configured (Tier 0), the drill SHALL still
   show the countdown and the "alert not sent" / composer-fallback path with the drill template,
   never a real send. A drill SHALL **never** send a real (non-drill) alert and SHALL never dial.
5. This spec SHALL **generalize** the crash-response "Developer / demo tools" toggle (Crash task
   23) into this global Demo mode: the Simulate crash entry point lives in Demo mode's tools, and
   Crash task 23's own separate toggle SHALL be updated to point here rather than duplicating the
   gate (Requirement 10; the crash spec's task-23 text is updated by this job without renumbering).
6. The drill SHALL be reachable **only** while demo mode is on (Requirement 9.2).

## Requirement 7: Seed and remove sample data

**Priority:** Important

**User story:** As a presenter, I want Home, History, and the weekly chart to look populated for
screenshots and the live walk-through, and I want to cleanly remove that sample data afterwards.

### Acceptance Criteria

1. WHILE demo mode is on THE demo tools SHALL offer **Seed sample data**, which inserts a small
   set of realistic finished rides (varied dates across the current and prior week, varied
   distances/durations, at least one with a route) through the existing `RideRepository`, each
   flagged as a **demo ride** (`isDemo == true`).
2. WHILE demo mode is on THE demo tools SHALL offer **Remove demo data**, which deletes **only**
   demo-flagged rides (real rides are never touched), using real deletion through the repository.
3. Seeding SHALL be **idempotent or clearly additive** (O-DM7): re-seeding SHALL NOT silently
   create confusing duplicates without the operator's intent; the tool SHALL state how many demo
   rides exist and offer to remove them first.
4. Seeded demo rides SHALL be **excluded from sync** (Requirement 9.3) and, per **O-DM2**,
   excluded from weekly stats unless the owner decides to include them for a fuller-looking demo.
5. WHEN the rider turns demo mode off THEN seeded demo rides SHALL remain in storage (so turning
   demo mode off doesn't destroy data) but SHALL keep their "Demo ride" tag and remain excluded
   from sync; Remove demo data SHALL be the explicit way to clear them.
6. The seed/remove actions SHALL report success or a plain, non-raw failure message
   (MVP Req 11.4) and SHALL be unit-testable against the in-memory repository.

## Requirement 8: Permission and state previews

**Priority:** Important

**User story:** As a presenter, I want to show the app's "unhappy path" states — location
denied, signal lost, storage unavailable, the crash countdown — without actually revoking
permissions or waiting for the real condition.

### Acceptance Criteria

1. WHILE demo mode is on THE demo tools SHALL offer **state previews** that render, without
   changing any real permission or persistent state: the **location-denied** Home state (MVP Req
   2.2), the **signal-lost** ride banner (MVP Req 5.3), the **storage-unavailable** notice (MVP
   Req 11.4 / `AppEnvironment.storageNotice`), and the **crash countdown and status** screens
   with the drill template (Crash Req 8, 11.6).
2. A state preview SHALL be visually consistent with the real state and SHALL be clearly dismissible,
   returning the app to its prior state with no side effects (no permission changed, no ride
   created, no alert sent).
3. The crash countdown preview SHALL reuse the real countdown UI driven by the drill path
   (Requirement 6), not a separate mock, so what judges see matches production; its "Call 911" is
   hidden (Crash Req 17.3).
4. The location-denied and storage-unavailable previews SHALL **not** actually deny location or
   break storage; they SHALL drive the existing view state only (an injected preview flag), and
   SHALL restore the real state on dismiss.
5. State previews SHALL be reachable only while demo mode is on (Requirement 9.2) and SHALL be
   VoiceOver-navigable (MVP Req 10.3).

## Requirement 9: Safety, honesty, and isolation

**Priority:** Demo-critical

**User story:** As the team, I want demo mode to be powerful on stage but incapable of causing a
real alert, a real upload, or any accidental change — and incapable of being hit by accident.

### Acceptance Criteria

1. **Zero behavior change when off.** WHILE demo mode is off THE app's observable behavior SHALL
   be identical to the build without this feature; all existing MVP and crash-response unit tests
   SHALL pass unchanged, and no simulated service SHALL be wired into the composition root.
2. **No accidental trigger.** Simulated rides, forced alerts, crash drills, and state previews
   SHALL be **impossible to invoke** unless demo mode is on; there SHALL be no default binding,
   gesture, or launch argument that triggers them in a normal (demo-off) build at runtime
   (a debug-only launch argument to *preset* the toggle for UI tests is allowed, O-DM3).
3. **No real sends or uploads.** Demo mode SHALL **never** send a real (non-drill) crash alert,
   SHALL **never** dial any number, and SHALL **never** upload demo-flagged rides. Demo rides
   SHALL be excluded from the sync path (MVP Req 12); the `SyncCoordinator` SHALL skip
   `isDemo == true` rides.
4. **Privacy invariants intact.** Demo mode SHALL NOT introduce any network call that the privacy
   rules forbid; `scripts/privacy-check.sh` SHALL continue to pass, and all demo copy SHALL obey
   the honesty rules (no claim of reliable detection or guaranteed delivery; drills labelled
   "DEMO — NOT REAL").
5. **Drill-only crash path.** Any crash flow reachable from demo mode SHALL use the `drill`
   template and the drill rules (Call 911 hidden, cap untouched); there SHALL be a unit test
   proving a demo/drill path produces **zero** non-drill notifier sends (Crash Req 19.2).
6. **Release-build availability (O-DM1).** Demo mode SHALL be available in Release builds behind
   the toggle (recommended, because the demo runs on the owner's device from Xcode/TestFlight),
   unless the owner decides to gate it to Debug/TestFlight only. Whatever is chosen, the toggle
   stays off by default and everything above still holds.
7. Turning demo mode off SHALL immediately and safely tear down every simulated service, the
   auto-trigger, any active simulated ride, and the badge (Requirement 1.4, 1.6).

## Requirement 10: Cross-spec consistency (crash-response generalization + SafetyKit note)

**Priority:** Important

**User story:** As the team, I want one place that owns "demo/developer tools", and I want the
crash-response spec corrected where it was wrong about Apple's crash-detection API.

### Acceptance Criteria

1. The crash-response "Developer / demo tools" toggle and its Simulate-crash entry point
   (Crash task 23, Crash Req 19.9) SHALL be **generalized into this Demo mode**: Demo mode owns
   the toggle and the Simulate-crash action, and the crash spec's task-23 description SHALL be
   updated (by this job, without renumbering or changing checkboxes) to reference this spec
   instead of defining its own separate toggle.
2. This job SHALL **correct the crash-response spec's claim** that "Apple's system Crash
   Detection is not available to third-party apps." Apple's **SafetyKit** framework (iOS 16+)
   exposes crash detection to apps via `SACrashDetectionManager` / `SACrashDetectionEvent`,
   subject to an Apple-granted entitlement and availability/authorization checks (see the
   crash-response design's capability investigation, updated by this job). The correction SHALL
   add a **`SafetyKitCrashDetector`** as an entitlement-gated implementation behind the existing
   `CrashDetector` protocol, alongside the no-op, the drill simulator, and the experimental
   motion detector, and SHALL note SafetyKit's **background-launch** behavior as a partial
   mitigation for the foreground-only limitation (O1) — for SafetyKit-detected events only.
3. The crash-response changes above SHALL be documentation-only edits to that spec's
   `requirements.md`, `design.md`, and `tasks.md` (a new entitlement+adapter+simulator-test task
   and an owner entitlement-application task appended to the stretch/future section with the next
   free numbers, no renumbering). All SafetyKit claims SHALL be marked "verify against current
   Apple docs".
4. Demo mode itself SHALL NOT depend on SafetyKit: the crash drill uses the `DebugCrashSimulator`
   and runs with no entitlement. SafetyKit is the crash-response spec's concern; Demo mode only
   references it for the correction in criterion 2–3.

---

## Non-functional notes

- **Testability:** the route source, the playback timing (via `Clock`), the stationary gate, the
  arming-bypass-for-drills rule, the demo-ride flag and its sync/stats exclusion, and the
  seed/remove logic are all pure or fake-driven and unit-tested. Real haptics, audio, and the
  live floating menu are verified on device.
- **Reliability target:** the demo runs **in the foreground with the screen on**, in airplane
  mode, on the iPhone 14 — the same reliable path as the MVP. No network is required for any
  demo-critical action (the only network a drill might use is the crash backend, which is Tier 1
  and optional).
- **Performance:** accelerated playback SHALL not block the main thread or drop the live map's
  smoothness (MVP Req 5.7).
- **Revisability:** demo services sit behind the existing protocols; removing demo mode is a
  localized change (delete the demo folder + the composition-root branch).

## Open decisions (for the owner)

- **O-DM1** Release-build availability: recommend **available in Release behind the toggle**
  (the demo runs from Xcode/TestFlight on the owner's device). Alternative: gate to
  Debug/TestFlight only.
- **O-DM2** Demo rides in weekly stats: recommend **excluded** (keeps This-Week numbers honest).
  Alternative: include them so Home looks fuller for the demo (then the weekly card must still
  be clearly in demo mode via the badge).
- **O-DM3** Debug launch argument to preset the toggle for UI tests: recommend **allowed in
  Debug only**, never a runtime trigger for the actions themselves.
- **O-DM4** Confirmation on enabling demo mode: recommend **optional one-tap confirmation**
  (not required) since it's off by default and harmless.
- **O-DM5** Tapping the DEMO MODE badge opens the demo tools: recommend **yes** as a convenience
  (badge remains non-destructive).
- **O-DM6** Turning demo mode off during a simulated ride: recommend **finalize-and-keep** the
  ride (flagged demo) rather than discard, so nothing is lost mid-demo; confirm.
- **O-DM7** Seed behavior on re-seed: recommend **report existing count and offer to remove
  first** (avoid silent duplicates) rather than blindly appending.
- **O-DM8** Scripted route count: recommend **one** good Boston loop for v1; more routes are a
  trivial later addition.

## Traceability

Every acceptance criterion maps to one or more tasks in `tasks.md` via `_Requirements:_`
annotations; `design.md` references these requirement numbers where it explains how each is
satisfied. Cross-spec work is traced to "Crash task N" in `../crash-response/tasks.md`.
