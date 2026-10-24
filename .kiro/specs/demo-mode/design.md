# Design — Whoosh Demo Mode

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O-DM1–O-DM8 (see "Owner resolution"). This document contains **no source code** by
design: the owner required requirements, design, and tasks to be reviewed before any
implementation. Types, protocols, and state are described in tables and diagrams; code is
written later, task by task, test-first (`tasks.md`).

## Overview

Demo mode is a thin, isolated subsystem layered on top of the finished ride-recording MVP and
the approved crash-response feature. It follows the same architecture: MVVM + service protocols,
the injected `Clock`, explicit state, fakes for every framework touchpoint, and one composition
root (`AppEnvironment`) that decides what to wire. Its central idea:

> **Demo mode changes nothing about the app's logic. It only changes which service
> implementations the composition root injects, and surfaces a few operator-driven tools and an
> unmissable badge. With the toggle off, none of it exists.**

```
                    ┌─────────────────────── DemoModeController (@Observable, MainActor) ───────────────────────┐
 Settings toggle ──▶│  isEnabled (persisted)   badge state   active simulated-ride handle   auto-trigger timer  │
                    └───────┬───────────────────────┬────────────────────────┬──────────────────────┬──────────┘
                            │ when ON               │                        │                      │
                            ▼                        ▼                        ▼                      ▼
                 SimulatedRouteTracker       HapticAudioAlertManager    DebugCrashSimulator     DemoDataSeeder
                 (LocationTracking)          (AlertManager, real)       (CrashDetector, drill)  (RideRepository)
                            │                        │                        │                      │
                            ▼                        ▼                        ▼                      ▼
                  RideSessionViewModel        RearAlertGate → AlertManager  CrashResponseCoordinator  isDemo rides
                  (UNCHANGED)                 (pure gate, UNCHANGED VM)      (UNCHANGED)              (excluded from sync/stats)
```

Everything the arrows point *into* (the ride engine, the alert protocol, the crash coordinator,
the repository) is unchanged. Demo mode is the stuff above the dashed line plus a handful of
pure rules and the badge/menus in the view layer.

### Revisability note

Each demo capability sits behind an existing protocol: the simulated ride is a `LocationTracking`
implementation (or a player driving the existing `FakeLocationTracker`); the forced alert uses
the existing `AlertManager`; the crash drill uses the crash-response `CrashDetector` seam and its
`DebugCrashSimulator`. Removing demo mode is a localized change: delete `Features/Demo/` +
`Services/DemoLocation/` and the single composition-root branch. Demo mode adds **no** new
network path and **no** new entitlement.

---

## What exists today (grounding)

Confirmed by reading the source in this worktree:

| Seam / type | Where | Relevant shape |
| ----------- | ----- | -------------- |
| `LocationTracking` (protocol) | `Services/Location/LocationTracking.swift` | `authorizationStatus`, `onAuthorizationChange`, `onLocation`, `onFailure`, `requestWhenInUseAuthorization()`, `startUpdating(accuracy:)`, `stopUpdating()`. Callbacks on the main actor. |
| `FakeLocationTracker` | `Services/Location/FakeLocationTracker.swift` | Ships in the app target (not just tests). Scripting API: `emit(_:)`, `emitPoints(_:)`, `changeAuthorization(_:)`, `fail(_:)`. Records `isUpdating`, `lastAccuracy`, counts. |
| `RideSessionViewModel` | `Features/Ride/RideSessionViewModel.swift` | `@Observable` `@MainActor`; owns `RideState`; takes `tracker: LocationTracking`, `clock: Clock`, `repository`, `tuning`. Drives the whole ride state machine from `onLocation`/timers. |
| `AlertManager` + `StubAlertManager` | `Services/Alerts/AlertManager.swift` | `protocol AlertManager { func fire(_ kind: AlertKind) }`; `AlertKind.cautionRearVehicle`. `StubAlertManager` is the only impl and does nothing. |
| `HazardDetector` + `NoopDetector` | `Services/Detection/HazardDetection.swift` | `onDetection` callback; `start()`/`stop()`. MVP ships `NoopDetector` (emits nothing). |
| `RideRepository` | `Services/Persistence/RideRepository.swift` | `save`, `allRides`, `ride(id:)`, `delete(id:)`, `deleteAll`. SwiftData + in-memory impls. `Ride`/`RideRecord` carry `syncStatus`. |
| `SyncCoordinator` | `Services/Sync/SyncCoordinator.swift` | `rideDidFinish`, `retryPending`, etc.; uploads only when `service.isEnabled`. Not wired yet (sync off). |
| `SettingsViewModel` | `Features/Settings/SettingsViewModel.swift` | `@Observable`, `UserDefaults`-backed (`accuracyDefaultsKey`), UI-framework-free. |
| `AppEnvironment` | `App/AppEnvironment.swift` | `@MainActor` composition root. `live()` / `preview(seeded:)`. Owns `repository`, `clock`, `detector`, `alertManager`, `storageNotice`, `settingsViewModel`, `homeViewModel`; factories `makeRideSession()`, `makeHistoryViewModel()`. |
| `Ride` model | `Models/Ride.swift` | Value type `Identifiable`, `Equatable`, `Hashable`; has `syncStatus` (defaulted init param added in MVP task 26). **Demo mode adds `isDemo`.** |
| Crash-response (approved) | `../crash-response/` | `CrashDetector`, `DebugCrashSimulator`, `CrashResponseCoordinator`, `drill` template, Call-911 hidden for drills (Crash Req 17.3), cap untouched (6.6), arming gate (5.4 / O10). Crash task 23 is the "Developer / demo tools" toggle revealing Simulate crash. |

Two things change in files *other code already owns*, kept minimal and additive:

- `Ride` / `RideRecord` gain an **`isDemo: Bool`** (default `false`), persisted like `syncStatus`
  (new defaulted init parameter + a defaulted stored attribute for lightweight migration) so
  every existing caller stays source-compatible and no `RideRepository` protocol change is
  needed. (O-DM2 governs whether stats also read it.)
- `SyncCoordinator` and `WeeklyStatsCalculator` learn to **skip `isDemo` rides** (sync always;
  stats per O-DM2). These are tiny, additive filters, each independently unit-tested.

---

## Architecture and layering

### New folders

| Layer / folder | Contents | Knows about | Must NOT import |
| -------------- | -------- | ----------- | --------------- |
| `Models/` (additions) | `DemoTuning` (constants), `DemoRideScript` + `ScriptedRoutePoint` (the pure scripted route), `DemoStatePreview` enum; plus the `isDemo` flag on `Ride` | Foundation | SwiftUI, CoreLocation, SwiftData, MapKit |
| `Metrics/` (additions, pure) | `RearAlertGate` (pure gate rule), `SimulatedRidePlayerCore` (pure timing/scaling math), `DemoArmingBypass` (drill-only arming rule) | Models | any framework/UI |
| `Services/DemoLocation/` | `SimulatedRouteTracker` (a `LocationTracking` impl that plays a `DemoRideScript` through the `Clock`), or a `SimulatedRidePlayer` driving the existing `FakeLocationTracker` (D-DM3) | Models, `LocationTracking`, `Clock` | SwiftUI, CoreLocation (it emits `RoutePoint`s directly; no `CLLocationManager`) |
| `Services/Alerts/` (addition) | `HapticAudioAlertManager` (real `AlertManager`: Core Haptics / `UIFeedbackGenerator` + a short `AVAudioSession` tone), alongside the existing `StubAlertManager` | Models | SwiftUI |
| `Services/Demo/` | `DemoDataSeeder` (builds + inserts/removes `isDemo` rides via `RideRepository`) | Models, `RideRepository` | SwiftUI |
| `Features/Demo/` | `DemoModeController` (`@Observable`, MainActor), `DemoToolsView(+VM)`, `DemoBadge`, `RideScreenDemoMenu`, `StatePreviewHost` | ViewModels, Theme, service protocols, crash-response coordinator | concrete framework services, SwiftData, CoreLocation |
| `Features/Settings/` (addition) | a "Demo mode" section in `SettingsView` bound to `DemoModeController` | ViewModels, Theme | — |
| `App/` (addition) | `AppEnvironment` gains a `demo` branch; `WhooshApp` mounts the badge + ride-screen menu + state-preview host | everything | — |

This obeys the MVP/crash layering tables: pure rules in `Models`/`Metrics`, framework access
behind protocols in `Services/*`, thin views in `Features/*`, wiring only in `App/`.

### Where the real haptic/audio alert lives (privacy)

`HapticAudioAlertManager` is the first real `AlertManager`. It uses `AVAudioSession` for the
short tone — which the crash-response privacy update (Crash design "privacy-check changes" rule
5) confines to `Services/Alerts/`. That rule already permits `AVAudioSession` in `Services/Alerts/`,
so the real alert manager lands in the allowed folder with **no privacy-script change needed for
demo mode**. It touches no network and no camera.

---

## DemoModeController (the heart of the feature)

`@Observable`, `@MainActor`. It is the single source of truth for "is demo mode on" and owns the
live demo activity. It is injected with the stores/seams it needs and is created by
`AppEnvironment` **always**, but it only *activates* simulated services when enabled.

| Member (described) | Purpose |
| ------------------ | ------- |
| `isEnabled: Bool` (persisted) | Reads/writes `UserDefaults` (`whoosh.demo.enabled`), default `false` (mirrors `SettingsViewModel`'s pattern). Setting it runs `activate()` / `deactivate()`. |
| `badgeVisible: Bool` (derived) | `== isEnabled`; views observe it for the DEMO MODE badge. |
| `autoAlertEvery: TimeInterval?` | When set, a `Clock`-scheduled repeating forced alert; `nil` = off. Cleared on `deactivate()`. |
| `activeSimulatedRide: Bool` (derived) | Whether a simulated ride is currently playing (so turning off can stop it, Req 1.6/5.7). |
| `statePreview: DemoStatePreview?` | Drives the preview host (`.locationDenied`, `.signalLost`, `.storageUnavailable`, `.crashCountdown`); `nil` = none. |
| `simulatedSpeedFactor: Double` | 1× default; accelerated factors (e.g. 4×, 10×) from `DemoTuning`. |

Intents (operator-driven, all no-ops while `isEnabled == false` as a defense-in-depth guard):
`startSimulatedRide()`, `stopSimulatedRide()`, `setSimulatedSpeed(_:)`, `fireRearAlertOnce()`,
`startAutoRearAlert(every:)` / `stopAutoRearAlert()`, `simulateCrashDrill()`, `seedSampleData()` /
`removeDemoData()`, `showStatePreview(_:)` / `dismissStatePreview()`.

`activate()` wires the simulated tracker factory and the real alert manager into the running
`AppEnvironment` session factory; `deactivate()` tears all of it down (stops the player, cancels
the auto-trigger, finalizes/stops any simulated ride per O-DM6, clears previews), returning the
app to the exact normal path.

### Dependency rule

Views observe `DemoModeController`; it depends on service **protocols** and the crash-response
coordinator's public intents, never on concrete framework types. In previews/tests it is built
with the fakes (`FakeLocationTracker`-based player, a recording `AlertManager` fake, a
`FakeCrashDetector`/fake coordinator, `InMemoryRideRepository`, a `TestClock`).

---

## Simulated ride

### Data: the scripted route (pure, Foundation-only)

```
DemoRideScript
├── name            e.g. "Charles River Loop"
├── points: [ScriptedRoutePoint]   ordered
│      ├── latitude, longitude
│      ├── offsetSeconds           seconds from ride start (monotonic)
│      ├── speedMetersPerSecond
│      ├── horizontalAccuracyMeters
│      └── marker?                 .pauseStart / .pauseEnd / .signalLossStart / .signalLossEnd
└── (derived) totalDuration, segment list
```

A single bundled **Charles River / Mass Ave loop** (O-DM8 = one route for v1) with realistic
coordinates, a **pause segment** (points carry `.pauseStart`/`.pauseEnd` markers), and a **short
signal-loss gap** (a window with `.signalLossStart`/`.signalLossEnd` where the player simply
withholds points long enough to trip the MVP's `signalLossTimeout`, default 8 s, so the real
amber banner appears — no special-casing in the ride engine). The script is a value type checked
into the app bundle as data/code; it imports Foundation only and is fully unit-testable.

### Playback: two implementation options (D-DM3, recommend A)

| Option | How | Pros | Cons |
| ------ | --- | ---- | ---- |
| **A. `SimulatedRouteTracker`** implements `LocationTracking` | A dedicated tracker that, on `startUpdating`, schedules each scripted point's delivery via the injected `Clock` (scaled by `simulatedSpeedFactor`), calls `onLocation`, and withholds points during the signal-loss gap. `authorizationStatus` returns `.authorizedWhenInUse`. | Cleanest seam; the ride VM is 100% unchanged; deterministic via `Clock`; never touches `CLLocationManager`, so "no real GPS mix" (Req 5.4) is structural | One more small type |
| **B. `SimulatedRidePlayer` drives the existing `FakeLocationTracker`** | A player object calls `tracker.emit(_:)` on a `Clock` schedule | Reuses the shipped fake | The fake's `startUpdating` is inert; the player must own timing; two objects to coordinate |

**Recommendation: A.** `SimulatedRouteTracker` is the `LocationTracking` the composition root
injects into `makeRideSession()` while a simulated ride is requested, so `RideSessionViewModel`
cannot tell the difference and never sees a real fix. The pure timing/scaling math
(`SimulatedRidePlayerCore`: given the script, a speed factor, and "now", which points are due) is
unit-tested independently of the `Clock` wrapper.

### No-mixing guarantee (Req 5.4)

`AppEnvironment.makeRideSession()` takes a tracker from a factory. While a simulated ride is
requested, the factory returns a `SimulatedRouteTracker`; otherwise a `CoreLocationTracker`. One
ride ⇒ one tracker ⇒ either all scripted or all real. A simulated ride is tagged `isDemo` at
finalize; a real ride can never be created from scripted points because the real tracker is never
a `SimulatedRouteTracker`.

### Speed and correctness (Req 5.3)

Accelerated playback scales the *delivery schedule* only. The scripted points keep their real
`offsetSeconds`, and the ride's active-duration/distance come from those timestamps and
coordinates exactly as for a real ride, so the summary is correct regardless of playback speed.
(The MVP's active-duration excludes paused spans; the script's pause markers drive the normal
pause/resume path.)

---

## Rear-vehicle alert: the gate and the forced demo

### The normal-mode gate (pure, `Metrics/RearAlertGate`) — Req 4.1

```
RearAlertGate.shouldDeliver(rideState, currentSpeed, tuning) -> Bool
   true  iff rideState == .recording && currentSpeed > tuning.minAlertSpeedMetersPerSecond
   false otherwise   (paused / signalLost / idle / finished, or speed ≤ threshold)
```

`minAlertSpeedMetersPerSecond` default **2 m/s** (~4.5 mph), in `DemoTuning` (or a shared tuning
constant). This gate is where a `HazardDetector` detection in normal mode is turned into an
`AlertManager.fire` call. Today `NoopDetector` emits nothing, so the gate is dormant; it is
specified now so that the *demo bypass* is well-defined and so the real detector (Role B) plugs
in behind a documented rule. The gate is a pure function with a truth-table unit test.

### The forced-alert demo — Req 4.3/4.4

```
DemoModeController.fireRearAlertOnce()
   guard isEnabled                      // defense in depth
   alertManager.fire(.cautionRearVehicle)   // the REAL path, bypassing the gate only
   // shows the same visual banner the real detection would
```

- It calls the **same** `AlertManager.fire(.cautionRearVehicle)` the gated path would, so judges
  see the real haptics/audio/banner.
- It **bypasses the stationary gate only** — it does not fabricate a `HazardDetection` (so
  nothing is logged as a real detection) and does not change the gate rule.
- `startAutoRearAlert(every:)` schedules repeats via the `Clock`; `deactivate()` cancels it.
- The visual banner copy is experimental ("Experimental rear-vehicle cue — demo"), passing the
  privacy check.

### The real alert manager — Req 4.7

`HapticAudioAlertManager` (new, in `Services/Alerts/`):

| Aspect | Design |
| ------ | ------ |
| Haptics | Core Haptics if available, else `UIFeedbackGenerator` (`.warning` notification feedback) fallback; prepared ahead to reduce latency |
| Audio | A short, non-alarming tone via `AVAudioSession` (`.playback` so the silent switch doesn't mute it, consistent with the crash countdown's audio decision); session activated briefly and released |
| Contract | `fire(_:)` returns immediately; heavy session work is kept off the hot path; never blocks or stops ride recording (existing `AlertManager` contract) |
| Honesty | It is a *cue*, not a guarantee; copy framed experimental |
| Isolation | Only file touching `AVAudioSession` in `Services/Alerts/` besides the crash feedback; no network, no camera |

It replaces `StubAlertManager` in the composition root **always** (it is correct in normal mode
too — the gate simply won't call it until a real detector exists), or only in demo mode if the
owner prefers to keep the stub for normal mode (D-DM5; recommend wiring the real one always since
it is inert until `fire` is called).

---

## Crash drill (reusing crash-response)

The drill path is entirely the crash-response feature's real code, invoked from demo mode:

```
DemoModeController.simulateCrashDrill()
   guard isEnabled
   crashResponseCoordinator.injectDrillSignal()   // via DebugCrashSimulator (Crash Req 5.3)
       → isDrill = true  → drill template "WHOOSH DEMO - NOT REAL"
       → Call 911 hidden (Crash Req 17.3)
       → does NOT consume the real-alert cap (Crash Req 6.6)
```

Three demo-specific rules, all expressed as pure helpers so they are testable and so the crash
engine stays untouched:

1. **Arming bypass for drills only (Req 6.3).** `DemoArmingBypass`: a drill signal is accepted
   even when `CrashArming` would be false (no active ride, stationary), **because** it is a
   drill. Real (non-drill) signals still obey `CrashArming`. This is a guard in how the drill
   signal is injected, not a change to `CrashArming`.
2. **Drill-only sends (Req 6.4, 9.5).** The drill uses the `drill` template exclusively; in
   Tier 0 (no backend/contact) it shows the countdown and the "alert not sent"/composer-fallback
   path with the drill template — never a real send, never a dial. A unit test asserts **zero**
   non-drill notifier sends from any demo path (Crash Req 19.2 / DRILL-1).
3. **Generalized toggle (Req 6.5 / 10.1).** The crash-response "Developer / demo tools" toggle
   (Crash task 23) is folded into Demo mode. The crash task-23 description is updated by this job
   to point here; demo mode owns the single entry point.

Interaction with the live floating menu: while the crash countdown takeover is up it sits above
everything (Crash Req 8.8 / D25), so the floating demo menu is hidden behind it and the DEMO MODE
badge is positioned not to obscure the "I'm OK — Cancel" control (Req 2.1).

---

## Seed and remove sample data

`DemoDataSeeder` (in `Services/Demo/`), pure-ish (builds value `Ride`s; persists via the
injected `RideRepository`):

| Operation | Behavior |
| --------- | -------- |
| `seed()` | Builds ~5–8 finished `Ride`s with `isDemo == true`: varied `startedAt` across the current and prior week (so the weekly chart has bars under O-DM2 = include, or stays empty under O-DM2 = exclude), varied distance/duration, ≥ 1 with a real route (reuse the scripted loop or `PreviewSeed`). Reports how many demo rides already exist and (O-DM7) offers to remove first rather than silently duplicating. |
| `removeDemo()` | Fetches `allRides()`, filters `isDemo == true`, and `delete(id:)`s exactly those — **real rides untouched**. Real deletion (MVP Req 7.4). |
| Errors | Surface a plain, non-raw message (MVP Req 11.4). |

Seeded rides are `isDemo`, so they are excluded from sync always (Req 9.3) and from stats per
O-DM2. `PreviewSeed` already exists for previews and can supply the shapes.

---

## State previews

`DemoStatePreview` drives a `StatePreviewHost` overlay that renders a real state without changing
real conditions:

| Preview | How it's rendered without side effects |
| ------- | -------------------------------------- |
| `.locationDenied` | Inject a preview authorization value into `HomeViewModel`'s state (the view already renders `LocationDeniedView` from a `HomeState`); the real `LocationTracking.authorizationStatus` is untouched; dismiss restores the real state. |
| `.signalLost` | Show the active-ride screen's amber banner via a preview flag; no real timeout needed. (During a *simulated ride*, the script's signal-loss gap produces it for real — this preview is for showing it without a ride.) |
| `.storageUnavailable` | Render the calm `storageNotice` alert copy (`AppEnvironment.storageNotice` text) without breaking the real store. |
| `.crashCountdown` | Launch the **real** drill countdown (Requirement 6) so the preview matches production; Call 911 hidden. |

Each preview is a transient overlay with a clear Dismiss; dismissing clears
`DemoModeController.statePreview` and leaves no residue (no permission changed, no ride created,
no alert sent). Previews are reachable only while demo mode is on.

---

## Composition-root wiring (`AppEnvironment`)

Minimal, additive, and the only place that branches on demo mode:

- `AppEnvironment` gains `let demo: DemoModeController`, built in both `live()` and
  `preview(...)`. In `live()` it is constructed with the real repository, a `SystemClock`, the
  real `HapticAudioAlertManager`, a `SimulatedRouteTracker` **factory**, and a reference to the
  crash-response coordinator (once that feature is wired; until then the drill entry point is
  disabled with a "Crash response not set up yet" note).
- `makeRideSession()` consults `demo.activeSimulatedRide`: if a simulated ride is requested it
  builds the session with a `SimulatedRouteTracker(script:clock:speedFactor:)`; otherwise the
  existing `CoreLocationTracker`. Everything else about the session is unchanged.
- The alert manager injected app-wide becomes `HapticAudioAlertManager` (inert until `fire`),
  replacing `StubAlertManager` (D-DM5).
- `WhooshApp` mounts: the `DemoBadge` overlay (visible iff `demo.badgeVisible`) above Home / the
  ride cover / emergency screens but below the crash takeover; the `RideScreenDemoMenu` on the
  active-ride cover; and the `StatePreviewHost`.
- **Off path is the identity path:** when `demo.isEnabled == false`, `makeRideSession()` returns
  exactly today's session, the badge is hidden, the menus/tools are absent, and the alert manager
  is never called by any demo path — so Req 9.1 ("zero behavior change when off") holds and every
  existing test is unaffected.

`preview(...)` builds `DemoModeController` over fakes so SwiftUI previews can show the badge,
tools, and a simulated ride deterministically.

---

## Demo-ride flag: sync and stats

| Concern | Change | Test |
| ------- | ------ | ---- |
| `Ride` / `RideRecord` | add `isDemo: Bool = false` (defaulted init param + defaulted stored attribute; lightweight migration like `syncStatus`). `RideRepository` protocol unchanged. | round-trip persistence incl. default for old rows |
| Sync (Req 9.3) | `SyncCoordinator.rideDidFinish(_:)` and `retryPending()` **skip** `ride.isDemo == true` (never upload). | demo ride ⇒ zero notifier/upload calls even when sync enabled |
| Weekly stats (O-DM2) | `WeeklyStatsCalculator.compute` gains an `includeDemo: Bool` (default per O-DM2 = exclude) or the caller filters `isDemo` before passing rides. Recommend the caller filters so the pure function stays unaware of demo. | with/without demo rides ⇒ correct totals |
| History/summary tag (Req 2.3) | rows/summary show a "Demo ride" tag when `isDemo`. | view-model mapping |

---

## Testing strategy

All logic is unit-tested with fakes; a `TestClock` makes playback and the auto-trigger
deterministic. Device checks cover real haptics/audio and the live menus.

| ID | Area | Scenario → assertion |
| -- | ---- | -------------------- |
| OFF-1 | Isolation | With `demo.isEnabled == false`, `makeRideSession()` returns a `CoreLocationTracker`-backed session; the alert manager is never fired by any demo path; badge hidden; tools absent. (Req 9.1) |
| OFF-2 | Isolation | The full existing MVP + crash unit suites pass unchanged when the demo files are present. (Req 9.1) |
| GATE-1..n | Rear gate | `RearAlertGate.shouldDeliver` truth table: recording+fast ⇒ true; recording+slow ⇒ false; paused/signalLost/idle/finished ⇒ false. (Req 4.1/4.2) |
| FORCE-1 | Forced alert | `fireRearAlertOnce()` while stationary and with no ride ⇒ exactly one `AlertManager.fire(.cautionRearVehicle)`; no `HazardDetection` logged. (Req 4.3) |
| FORCE-2 | Auto-trigger | `startAutoRearAlert(every: n)` fires every n via `TestClock`; `stopAutoRearAlert()`/`deactivate()` stops it. (Req 4.4) |
| FORCE-3 | No bypass when off | `fireRearAlertOnce()` is a no-op while `isEnabled == false`. (Req 9.2) |
| SIM-1 | Player core | `SimulatedRidePlayerCore` returns the correct due points for a given script/speed/now (1× and accelerated). (Req 5.3/5.8) |
| SIM-2 | Ride integration | Running a simulated ride through the real `RideSessionViewModel` + `SimulatedRouteTracker` + `TestClock` reproduces: growing route, climbing metrics, a pause via the pause marker, the amber signal-lost banner via the gap, correct summary. (Req 5.1/5.2) |
| SIM-3 | Speed correctness | 1× and 10× produce the **same** distance/active-duration/avg-speed summary. (Req 5.3) |
| SIM-4 | No mixing | A simulated-ride session's tracker is a `SimulatedRouteTracker`; it never emits a real fix; a real session never gets scripted points. (Req 5.4) |
| SIM-5 | Flag + exclusion | A finished simulated ride has `isDemo == true`; `SyncCoordinator` skips it; stats exclude it per O-DM2. (Req 5.5/9.3) |
| SIM-6 | Teardown | `deactivate()` during a simulated ride stops the player and finalizes/discards per O-DM6; tracker stops emitting. (Req 1.6/5.7) |
| DRILL-1 | Crash drill | `simulateCrashDrill()` runs the real coordinator with the `drill` template, Call 911 hidden, cap unchanged; **zero** non-drill notifier sends. (Req 6.1/6.2/9.5; Crash Req 19.2/19.9) |
| DRILL-2 | Arming bypass | A drill is accepted while stationary / no ride (bypass) **but** a real signal in the same state is still ignored (`CrashArming` unchanged). (Req 6.3) |
| SEED-1 | Seed/remove | `seed()` inserts N `isDemo` rides; `removeDemo()` deletes only those; real rides survive; re-seed reports existing count (O-DM7). (Req 7.1/7.2/7.3) |
| PREV-1..4 | State previews | Each preview renders and dismisses with no side effect (no permission/ride/alert change); crash preview reuses the real drill countdown. (Req 8) |
| SAFE-1 | Safety | No demo path reaches a real (non-drill) send or a dial; demo rides never upload. (Req 9.3/9.5) |
| BADGE-1 | Labelling | Badge visible iff `isEnabled`; disappears immediately on off; demo-ride tag persists in storage. (Req 2) |

Device checks (not automatable), recorded in a manual-QA note (task below): real haptics and the
short tone with the silent switch on; the floating demo menu not obscuring metrics or the "I'm
OK — Cancel" takeover; VoiceOver on the tools, badge, and previews; the full on-stage run
(enable demo → seed → simulated ride showing map/metrics/pause/signal-loss/summary → forced
alert → crash drill → disable) in airplane mode on the iPhone 14.

---

## Decisions

Status: **Proposed** = recommended default pending owner review; **OPEN** = needs an owner
decision (mirrors the O-DM items in `requirements.md`).

| # | Decision | Choice | Why | Status |
| - | -------- | ------ | --- | ------ |
| D-DM1 | Single Settings toggle, off by default, persisted | `DemoModeController.isEnabled` in `UserDefaults` | Matches the brief and `SettingsViewModel`'s pattern | Proposed |
| D-DM2 | Unmissable badge on Home/ride/emergency | Icon + text overlay via `DemoBadge`, below the crash takeover | Nobody mistakes demo output for real | Proposed |
| D-DM3 | Simulated ride transport | `SimulatedRouteTracker` implementing `LocationTracking` (Option A) | Ride VM 100% unchanged; deterministic; no GPS mixing by construction | Proposed |
| D-DM4 | Scripted route | One bundled Charles River / Mass Ave loop with a pause segment + signal-loss gap, pure/Foundation-only | Realistic, testable, shows paused + signal-lost states | Proposed (O-DM8) |
| D-DM5 | Alert manager wiring | Ship `HapticAudioAlertManager` always (inert until `fire`); gate controls normal calls | Real alert exists for the demo; normal mode unchanged because the gate won't fire it | Proposed |
| D-DM6 | Rear-alert gate | Pure `RearAlertGate`: recording ∧ speed > 2 m/s | Defines the stationary-rest rule so the demo bypass is precise | Proposed |
| D-DM7 | Forced alert | Calls the real `AlertManager.fire`, bypassing the gate **only**; no fabricated detection | Honest; shows real feedback standing still | Proposed |
| D-DM8 | Crash drill | Reuse crash-response `DebugCrashSimulator` + coordinator; drill template; arming bypass for drills only | One real flow; no real send; stationary demo | Proposed |
| D-DM9 | Developer-tools ownership | Demo mode owns the toggle; crash task 23 points here | Single source; no duplicate gate | Proposed (edits crash spec) |
| D-DM10 | Demo-ride flag | `isDemo` on `Ride`/`RideRecord`; sync always skips; stats skip per O-DM2 | Demo data never uploads; stats stay honest | Proposed (O-DM2) |
| D-DM11 | State previews | Drive existing view states via injected preview flags; crash preview = real drill | Matches production; no side effects | Proposed |
| D-DM12 | Release availability | Available in Release behind the toggle | Demo runs from Xcode/TestFlight on the owner's device | **OPEN O-DM1** |
| D-DM13 | Weekly stats inclusion | Exclude demo rides | Keep This-Week numbers honest | **OPEN O-DM2** |
| D-DM14 | Off-during-sim behavior | Finalize-and-keep the simulated ride | Don't lose data mid-demo | **OPEN O-DM6** |
| D-DM15 | Re-seed behavior | Report count + offer remove-first | Avoid silent duplicates | **OPEN O-DM7** |
| D-DM16 | Enable confirmation | Optional one-tap confirm | Harmless; off by default | **OPEN O-DM4** |

### Owner resolution (October 24, 2026)

The iOS owner approved this spec and accepted every recommendation; this table is binding.

| # | Resolution |
| - | ---------- |
| O-DM1 | Demo mode is available in Release builds, behind the Settings toggle (off by default). |
| O-DM2 | Demo rides are excluded from This-Week stats (and always from sync). |
| O-DM3 | A launch argument that presets the toggle is allowed in Debug builds only (for UI tests). |
| O-DM4 | Enabling demo mode shows an optional one-tap confirmation. |
| O-DM5 | Tapping the DEMO MODE badge opens the demo tools. |
| O-DM6 | Turning demo mode off during a simulated ride finalizes and keeps that (demo-flagged) ride. |
| O-DM7 | Re-seeding reports the existing demo-ride count and offers to remove them first; never silent duplicates. |
| O-DM8 | One scripted Boston loop for v1; more routes later. |

### Open decisions for the owner (summary, now resolved above)

- **O-DM1 (D-DM12)** Release-build availability (recommend: yes, behind the toggle).
- **O-DM2 (D-DM13)** Demo rides in weekly stats (recommend: exclude).
- **O-DM3** Debug-only launch argument to preset the toggle for UI tests (recommend: allow, Debug
  only; never a runtime action trigger).
- **O-DM4 (D-DM16)** Require a confirmation when enabling (recommend: optional).
- **O-DM5** Tapping the badge opens the tools (recommend: yes).
- **O-DM6 (D-DM14)** Off-during-simulated-ride: finalize vs. discard (recommend: finalize-keep).
- **O-DM7 (D-DM15)** Re-seed behavior (recommend: report + remove-first).
- **O-DM8 (D-DM4)** One scripted route for v1 (recommend: yes).

## Demo rear feed (shipped, October 24, 2026 — Requirement 11)

The rear-camera headline — recording plus experimental vehicle detection with proximity dings —
can be shown standing still indoors by replaying a bundled road clip through the **real** vision
pipeline. This is demo-only and records/uploads nothing.

**Files:**

- `Whoosh/Services/Detection/DemoVideoFeed.swift` — `@MainActor @Observable` feed. Loads
  `DemoRearFeed.mp4` from the app bundle into an `AVPlayer` with an `AVPlayerItemVideoOutput`,
  loops it, and on a ~10 Hz timer pulls the newest `CVPixelBuffer`, wraps it in the project's
  `VideoFrame`, and feeds the **real** `VisionVehicleConsumer` (WhooshVision YOLO). One inference
  runs at a time (frames arriving while busy are skipped); the first frame after a loop is flagged
  `isDiscontinuity` so the approach estimator resets. Publishes `boxes`, `proximity`,
  `alertCount`, and `modelState`.
- `Whoosh/Features/Demo/DemoVideoFeedView.swift` — the full-screen Settings presentation and the
  shared `DemoFeedSurface` (player layer + `DetectionOverlay` at the clip's aspect ratio) reused
  on the ride screen.
- `Whoosh/Resources/Demo/DemoRearFeed.mp4` — the bundled recorded road clip.

**Proximity logic (pure, inside `DemoVideoFeed`):** only the **main car** counts — the largest
vehicle box (`car`/`truck`/`bus`/`motorcycle`, confidence ≥ 0.5) with centre x in 0.25…0.75 and
bottom edge in the near half (`y + height > 0.45`), so parked cars at the edges and small cars far
back are ignored. It is **dangerous** when area ≥ 0.12 **or** it is still growing ≥ 4% over the
last ~0.6 s at area ≥ 0.03 (a short `mainAreaHistory` window drives the growth check). The danger
holds 1 s after the last approaching frame so dings don't stutter. Closeness maps box area 0.02 →
0 and 0.22+ → 1; the ding interval is `1.4 − closeness · 1.15` s (≈1.4 s far → 0.25 s full frame).
Only the main box is marked `isApproaching` so just it is highlighted in the alert colour.

**Dinging and the fan-out:** each due ding plays the phone tone (`AudioSessionTonePlayer`) and
calls `onDing`, which the composition root (`DemoModeController.makeVideoFeed()`) routes to
`AlertManager.fireUrgent(.cautionRearVehicle)`. `fireUrgent` (added to the `AlertManager` protocol
with a `fire`-based default; `FanOutAlertManager` overrides it) delivers **ignoring the per-kind
cooldown**, so the watch buzzes on every ding and the cue accelerates as the car closes in, while
genuine ride cues still obey the 3 s cooldown via `fire`.

**Ride-screen integration:** `WhooshApp.beginRide` sets `demoFeed = environment.demo.isEnabled ?
environment.demo.makeVideoFeed() : nil`. `ActiveRideView` shows `DemoFeedSurface` + a closeness
bar in place of the map when `demoFeed` is set, surfaces the detection chip as **on**, and
suppresses the GPS signal-lost banner and its VoiceOver announcement (`demoFeed == nil` guards).
`proceedToRideSetup` and `startRide` skip Mount & frame and the watch-connect step for demo rides.

**Badge removal (owner request):** the always-on `DemoBadge` is no longer placed on Home, the ride
screen, or the emergency screens (it now appears only in its own `#Preview`). The `DemoBadge` view
and `DemoModeController.badgeVisible` remain; the ride-screen demo menu (`RideScreenDemoMenu`) is
still gated on `badgeVisible`, so the demo triggers stay reachable only while demo mode is on.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Demo output mistaken for real | Judges/users confused; trust damage | Unmissable badge + "Demo ride" tag + drill "DEMO — NOT REAL"; never sends/uploads |
| Demo mode left on by accident | Real rides tagged demo, excluded from sync/stats | Off by default; immediate restore on toggle off; badge always visible while on |
| A demo path sends a real alert/dial | Harm, embarrassment | Drill-only template; Call 911 hidden; unit test asserts zero non-drill sends; no dial API in any demo path |
| Demo ride mixed with real GPS | Corrupt data | One tracker per ride by construction (D-DM3); no-mixing unit test |
| Accelerated playback drops map smoothness | Janky demo | Timing off the main hot path; summary math independent of speed; perf device check |
| Scope creep into a QA harness | Time sink | Operator-driven tools only; no scripting API; one route |
| Real alert manager latency/haptics | Weak demo | Prepare haptics ahead; `.playback` audio; device check |
