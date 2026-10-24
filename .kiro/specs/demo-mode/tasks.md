# Implementation Plan — Whoosh Demo Mode

Small, ordered, verifiable tasks for the **iOS app owner**. **No code exists for this feature yet
and none may be written until the owner approves this spec** (`requirements.md`, `design.md`,
this file).

This plan is separate from the ride-recording MVP plan (`../ride-recording-mvp/tasks.md`, tasks
1–28) and the crash-response plan (`../crash-response/tasks.md`). Task numbers here are
independent; cross-spec references say "MVP task N" and "Crash task N".

The crash drill (tasks 11–12) depends on the crash-response feature's Tier 0 being wired
(Crash tasks through at least 23 and 26). Demo mode's other tools (toggle, badge, simulated ride,
forced alert, seed, previews) depend **only** on the finished MVP.

## Conventions

- `(test-first)` — write failing unit tests from the referenced acceptance criteria, then
  implement until green (the existing `.kiro/hooks/test-first-before-task.json` applies).
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers in this plan; cross-spec deps say "MVP task N"
  / "Crash task N".
- Each task is one reviewable commit or small PR. **Commits are made by the owner**, never by an
  automated agent unless asked.
- Run the unit suite (`scripts/test.sh`) before marking a task done. Tasks touching real haptics,
  audio, or the live floating menu also need the device check named in the task and an entry in
  the manual-QA note (task 15).
- **Copy rule for every task:** demo/experimental copy must pass `scripts/privacy-check.sh`
  (no claim of reliable detection or guaranteed delivery; drills say "DEMO — NOT REAL").
- **Isolation rule for every task:** nothing a task adds may change behavior while demo mode is
  off; the existing MVP and crash suites must stay green (Requirement 9.1).

---

## Phase 0 — Gate

- [x] 0. `[Owner]` `[DEMO]` Review and approve the spec; resolve the open decisions
  - Read `requirements.md`, `design.md`, and this plan. Decide **O-DM1..O-DM8** (or accept the
    recommended defaults) and record the answers under `design.md` "Decisions".
  - Confirm the demo-ride/stats choice (O-DM2) and Release availability (O-DM1), since they shape
    tasks 3, 8, and 13.
  - _Verify:_ spec status changed to "Approved"; open decisions marked resolved.
  - _Requirements:_ 1 (scope), 9 (isolation), 10 (cross-spec)

## Phase 1 — Pure core and the demo-ride flag (no frameworks, test-first)

- [ ] 1. `[iOS]` `[DEMO]` `DemoTuning`, scripted-route model, and the pure player core (test-first)
  - Add `DemoTuning` (speed factors, `minAlertSpeedMetersPerSecond = 2`, auto-alert interval
    default), `DemoRideScript` + `ScriptedRoutePoint` + segment markers, and `DemoStatePreview`,
    all Foundation-only. Add `SimulatedRidePlayerCore` (pure: script × speed × now → due points,
    with the signal-loss gap withholding points).
  - Author the single Charles River / Mass Ave loop as bundled data (coordinates, offsets,
    speeds, accuracies, one pause segment, one signal-loss gap).
  - Unit tests (test-first): due-point selection at 1× and accelerated; pause and signal-loss
    markers land where expected; monotonic offsets; speed scaling preserves total scripted
    duration.
  - _Requirements:_ 5.2, 5.3, 5.8
  - _Depends on:_ 0

- [ ] 2. `[iOS]` `[DEMO]` `RearAlertGate` pure gate rule (test-first)
  - Implement `RearAlertGate.shouldDeliver(rideState:currentSpeed:tuning:)`: true only in
    `recording` with speed > `minAlertSpeedMetersPerSecond`; false for paused/signalLost/idle/
    finished or slow.
  - Unit tests: the full truth table, including the threshold boundary.
  - _Requirements:_ 4.1, 4.2
  - _Depends on:_ 1

- [ ] 3. `[iOS]` `[DEMO]` `isDemo` flag on `Ride`/`RideRecord` + sync/stats exclusion (test-first)
  - Add `isDemo: Bool = false` to the domain `Ride` (defaulted init param, source-compatible) and
    to `RideRecord` as a defaulted stored attribute (lightweight migration, like `syncStatus`);
    map both ways in the SwiftData and in-memory repositories. **`RideRepository` protocol
    unchanged.**
  - Make `SyncCoordinator.rideDidFinish`/`retryPending` **skip** `isDemo` rides; have the stats
    caller filter `isDemo` before `WeeklyStatsCalculator.compute` (per O-DM2; if O-DM2 = include,
    skip this filter and document it).
  - Unit tests: round-trip persistence incl. default for pre-existing rows; a demo ride yields
    **zero** upload calls even with sync enabled; weekly stats exclude (or include) demo rides per
    O-DM2.
  - _Requirements:_ 5.5, 7.4, 9.3
  - _Depends on:_ 0

- [ ] 4. `[iOS]` `[DEMO]` `DemoArmingBypass` rule for drills (test-first)
  - Pure helper: a **drill** signal is accepted even when `CrashArming` is false; a real
    (non-drill) signal still obeys `CrashArming`. No change to the crash spec's `CrashArming`.
  - Unit tests: drill accepted while stationary/no-ride; real signal in the same state rejected.
  - _Requirements:_ 6.3
  - _Depends on:_ 0

## Phase 2 — Services (seams and fakes, test-first)

- [ ] 5. `[iOS]` `[DEMO]` `SimulatedRouteTracker` (`LocationTracking`) (test-first)
  - Implement `SimulatedRouteTracker(script:clock:speedFactor:)` conforming to `LocationTracking`:
    on `startUpdating` it schedules each due point via the injected `Clock` scaled by the speed
    factor, calls `onLocation`, withholds points across the signal-loss gap, and reports
    `authorizationStatus == .authorizedWhenInUse`. It never touches `CLLocationManager`.
  - Unit tests with a `TestClock`: points arrive in order on schedule; accelerating changes the
    schedule, not the data; the gap produces no points long enough to trip the MVP signal-loss
    timeout; `stopUpdating` halts emission.
  - _Requirements:_ 5.1, 5.3, 5.4, 5.7, 5.8
  - _Depends on:_ 1

- [ ] 6. `[iOS]` `[DEMO]` `HapticAudioAlertManager` (real `AlertManager`)
  - Implement a real `AlertManager` in `Services/Alerts/`: Core Haptics (fallback
    `UIFeedbackGenerator`) + a short `.playback` `AVAudioSession` tone; `fire(_:)` returns
    immediately; session activated briefly and released; failures degrade silently. Only file
    besides crash feedback touching `AVAudioSession`, which the privacy rule already allows here.
    The existing `StubAlertManager` stays for tests that want an inert manager.
  - _Verify (device):_ a tap produces a haptic + short tone with the silent switch on; no UI block.
  - _Requirements:_ 4.7
  - _Depends on:_ 0

- [ ] 7. `[iOS]` `[DEMO]` `DemoDataSeeder` (test-first)
  - Build ~5–8 finished `isDemo` rides (varied dates across the current/prior week, varied
    distance/duration, ≥ 1 with a route) and persist via `RideRepository`; `removeDemo()` deletes
    only `isDemo` rides; report existing demo-ride count and offer remove-first on re-seed
    (O-DM7); plain non-raw error messages.
  - Unit tests against `InMemoryRideRepository`: seed count; remove deletes only demo rides; real
    rides survive; re-seed reports the count.
  - _Requirements:_ 7.1, 7.2, 7.3, 7.5, 7.6
  - _Depends on:_ 3

## Phase 3 — Controller and composition (test-first)

- [ ] 8. `[iOS]` `[DEMO]` `DemoModeController` core (test-first)
  - `@Observable`, MainActor. `isEnabled` persisted in `UserDefaults` (default off, survives
    relaunch); `badgeVisible` derived; `simulatedSpeedFactor`; `statePreview`. Intents:
    `startSimulatedRide`/`stopSimulatedRide`/`setSimulatedSpeed`, `fireRearAlertOnce`,
    `startAutoRearAlert(every:)`/`stopAutoRearAlert` (via `Clock`), `seedSampleData`/
    `removeDemoData`, `showStatePreview`/`dismissStatePreview`, and `simulateCrashDrill` (wired in
    task 11). `activate()`/`deactivate()` manage simulated services and tear everything down on
    off. Every intent is a no-op while `isEnabled == false`.
  - Unit tests (fakes + `TestClock`): persistence + default off; FORCE-1/FORCE-2/FORCE-3;
    auto-trigger start/stop; deactivate stops the auto-trigger and clears state; forced alert
    bypasses the gate but logs no `HazardDetection`.
  - _Requirements:_ 1.2, 1.4, 1.6, 4.3, 4.4, 4.6, 9.2, 9.7
  - _Depends on:_ 2, 5, 6, 7

- [ ] 9. `[iOS]` `[DEMO]` Composition-root wiring (test-first where possible)
  - `AppEnvironment` builds `demo: DemoModeController` in `live()` and `preview(...)`.
    `makeRideSession()` returns a `SimulatedRouteTracker`-backed session iff a simulated ride is
    requested, else the existing `CoreLocationTracker` session (no mixing). Inject
    `HapticAudioAlertManager` app-wide (inert until fired), per D-DM5. **Off path = identity
    path:** with demo off, everything equals today's wiring.
  - Unit tests: OFF-1 (demo off ⇒ `CoreLocationTracker` session, alert never fired by a demo
    path, badge hidden); SIM-4 (simulated-ride session uses `SimulatedRouteTracker`); SIM-5
    (finished simulated ride `isDemo`, skipped by sync).
  - _Requirements:_ 5.1, 5.4, 5.5, 9.1, 9.3, 9.6
  - _Depends on:_ 8

## Phase 4 — UI (thin views over the tested controller)

- [ ] 10. `[iOS]` `[DEMO]` Settings "Demo mode" section, badge, and ride-screen demo menu
  - Add the off-by-default "Demo mode" section to `SettingsView` (own section, plain explanation,
    optional enable confirmation per O-DM4) bound to `DemoModeController`. Add `DemoBadge` (icon +
    text) mounted in `WhooshApp` on Home / ride cover / emergency screens, below the crash
    takeover. Add the collapsible `RideScreenDemoMenu` on the active-ride cover (Simulate vehicle,
    Simulate crash, speed control), ≥ 60 pt targets, VoiceOver-labelled, hidden behind a crash
    takeover.
  - _Verify (device):_ toggling on/off shows/hides the badge and tools immediately; the menu
    never obscures the three metrics or hold-to-stop; VoiceOver reads the badge and menu.
  - _Requirements:_ 1.1, 1.3, 1.5, 1.7, 2.1, 2.2, 2.5, 2.6, 3.1, 3.2, 3.4, 3.5, 3.6
  - _Depends on:_ 9

- [ ] 11. `[iOS]` `[DEMO]` Demo tools panel: simulated ride, forced alert, seed/remove
  - Build `DemoToolsView(+VM)` in the Settings section: start/stop a simulated ride (+ speed),
    Simulate approaching vehicle (+ auto every N), Seed sample data / Remove demo data. Wire each
    control to the already-tested `DemoModeController` intents. Show the "Demo ride" tag in
    History/summary rows when `isDemo` (Req 2.3).
  - _Verify (device):_ a simulated ride plays standing still — map draws, metrics climb, the
    pause segment and amber signal-lost banner appear, hold-to-stop finalizes, the summary and a
    tagged History row are correct; the forced alert fires real haptics/audio/banner while
    stationary; seed populates Home/History and remove clears only demo rides.
  - _Requirements:_ 2.3, 3.1, 4.3, 4.4, 4.5, 5.1, 5.2, 5.6, 7.1, 7.2
  - _Depends on:_ 10

- [ ] 12. `[iOS]` `[DEMO]` Crash drill integration
  - Wire `DemoModeController.simulateCrashDrill()` to the crash-response `CrashResponseCoordinator`
    via `DebugCrashSimulator`, applying `DemoArmingBypass` (drills only). Surface Simulate crash in
    the demo tools and the ride-screen menu. Confirm the drill shows the real countdown with the
    `drill` template, Call 911 hidden, and (Tier 0) the "alert not sent"/composer-fallback path —
    never a real send.
  - Unit tests: DRILL-1 (real coordinator, drill template, cap untouched, **zero** non-drill
    sends); DRILL-2 (bypass for drills only). If the crash feature isn't wired yet, the entry
    point shows a disabled "Crash response not set up yet" note and the tests use the crash fakes.
  - _Requirements:_ 6.1, 6.2, 6.4, 6.6, 9.5
  - _Depends on:_ 8, Crash task 23, Crash task 26
  - _Note:_ Crash task 23's description is updated by the spec-writing job to point here; this task
    does the actual wiring once the crash coordinator exists.

- [ ] 13. `[iOS]` `[DEMO]` State previews
  - Build `StatePreviewHost` driving the four `DemoStatePreview` cases via injected preview flags:
    location-denied Home, signal-lost banner, storage-unavailable notice, and the crash countdown
    (reusing the real drill countdown). Each dismisses cleanly with no side effect.
  - _Verify (device):_ each preview renders like the real state and leaves no residue on dismiss
    (no permission changed, no ride created, no alert sent).
  - _Requirements:_ 8.1, 8.2, 8.3, 8.4, 8.5
  - _Depends on:_ 10, 12

## Phase 5 — Prove it

- [ ] 14. `[iOS]` `[DEMO]` Isolation and safety regression
  - Confirm, with demo mode off, the full existing MVP + crash unit suites pass unchanged (OFF-2)
    and the composition root returns today's wiring. Add a safety test (SAFE-1) proving no demo
    path reaches a real (non-drill) send or a dial and demo rides never upload. Confirm
    `scripts/privacy-check.sh` passes with the demo files present.
  - _Requirements:_ 9.1, 9.2, 9.3, 9.4, 9.5, 9.7
  - _Depends on:_ 9, 12

- [ ] 15. `[iOS]` `[DEMO]` Manual QA note and on-stage rehearsal
  - Create `.kiro/specs/demo-mode/manual-qa.md` (same format as the MVP/crash checklists): real
    haptics + tone with the silent switch on, the floating menu not obscuring metrics or the
    "I'm OK — Cancel" takeover, VoiceOver on tools/badge/previews, and the full on-stage run
    (enable → seed → simulated ride showing map/metrics/pause/signal-loss/summary → forced alert
    → crash drill → disable) in **airplane mode** on the iPhone 14. Tick it.
  - _Requirements:_ 1.4, 2.1, 3.2, 3.6, 5.2, 6.1 (end-to-end)
  - _Depends on:_ 11, 12, 13, 14

---

## Cross-spec edits (done by the spec-writing job, not a code task)

These are documentation edits already applied to the crash-response spec and steering; listed
here for traceability:

- **Crash task 23** description updated to point to this Demo mode spec for the developer/demo
  tools toggle and the Simulate-crash entry point (no renumbering, no checkbox change).
- **Crash `design.md`** capability investigation (row 2) and detector section corrected for
  SafetyKit; a `SafetyKitCrashDetector` added behind the `CrashDetector` seam with the
  background-launch note as a partial O1 mitigation.
- **Crash `requirements.md`** detection requirement (Req 5) updated for SafetyKit.
- **Crash `tasks.md`** gained a `SafetyKitCrashDetector` entitlement+adapter+simulator-test task
  and an owner entitlement-application task appended to the stretch/future section (next free
  numbers, no renumbering).
- **MVP `tasks.md`** gained a one-line cross-reference to this spec.
- **`.kiro/steering/product.md`** gained a short "Demo mode" line.

See Requirement 10 for the acceptance criteria these satisfy.

---

## Proposed order of implementation

1. **Gate:** 0 (owner resolves O-DM1..O-DM8).
2. **Pure core + flag (parallelizable):** 1, 2, 3, 4 can all proceed in parallel after 0 (they
   touch different files). 2 needs 1's `DemoTuning`.
3. **Services (parallelizable):** 5 (needs 1), 6, 7 (needs 3) can proceed in parallel.
4. **Controller + wiring:** 8 (needs 2, 5, 6, 7) → 9.
5. **UI:** 10 (needs 9) → 11; 12 in parallel with 11 once Crash tasks 23/26 are ready; 13 after
   10 + 12.
6. **Prove it:** 14 (needs 9, 12) → 15 (needs 11, 12, 13, 14).

**Can run in parallel:**
- After task 0: **1, 2, 3, 4** (different files; 2 waits on 1's tuning).
- After the pure core: **5, 6, 7** (tracker, alert manager, seeder are independent).
- **11 and 12** (tools panel vs. crash-drill wiring) once their deps are met.

**Critical path to a demo-ready build (no crash drill):** 0 → 1 → 5 → 8 → 9 → 10 → 11
(+ 2, 3, 6, 7 feeding 8/9). The crash drill (12) and state previews (13) layer on after the
crash feature's Tier 0 is wired.

## Kiro hooks

- **Existing, still sufficient:** `privacy-guard-on-save` runs `scripts/privacy-check.sh` on every
  saved Swift file (demo copy must pass it; `AVAudioSession` stays confined to `Services/Alerts/`).
  `run-tests-after-task` and `test-first-before-task` apply unchanged. No new hook is needed.

## Definition of done (per task)

1. Code matches the layering table (no illegal imports); framework access is behind a protocol
   with a fake.
2. New or changed logic has unit tests from the referenced acceptance criteria; the full suite is
   green (`scripts/test.sh`), **including the unchanged MVP and crash suites** (Requirement 9.1).
3. Device verification done and logged in `manual-qa.md` where the task calls for it.
4. No new first-party compiler warnings.
5. **Isolation intact:** with demo mode off, behavior is unchanged; no simulated service is wired.
6. **Safety intact:** no demo path sends a real (non-drill) alert or dials; demo rides never
   upload; drills use the `drill` template with Call 911 hidden; honest copy passes
   `scripts/privacy-check.sh`.

## Traceability (requirement → tasks)

| Req | Tasks |
| --- | ----- |
| 1 Toggle | 0, 8, 10, 14 |
| 2 Labelling | 10, 11 |
| 3 Tools + menu | 10, 11, 12, 13 |
| 4 Rear gate + forced alert | 2, 6, 8, 11 |
| 5 Simulated ride | 1, 3, 5, 9, 11 |
| 6 Crash drill | 4, 12 |
| 7 Seed/remove | 3, 7, 11 |
| 8 State previews | 13 |
| 9 Safety/isolation | 3, 9, 12, 14 |
| 10 Cross-spec | cross-spec edits (above), 12 |
