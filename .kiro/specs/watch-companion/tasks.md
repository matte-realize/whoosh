# Implementation Plan — Whoosh Apple Watch Companion

Small, ordered, verifiable tasks. **No code exists for this feature yet and none may be written until
the owner approves this spec** (`requirements.md`, `design.md`, this file) **and the feasibility spike
(task 1) returns a go decision.**

Spec status: **APPROVED** by the iOS owner (October 24, 2026) with the recommended answers to O-W1–O-W11 (`design.md`, "Owner resolution"). Owner's watch: Apple Watch SE (2nd generation).

This plan is separate from the ride-recording MVP plan (`../ride-recording-mvp/tasks.md`), the
crash-response plan (`../crash-response/tasks.md`), and the rear-camera plan
(`../rear-camera/tasks.md`; its task 34 is the placeholder this spec fulfils). Task numbers here are
independent; cross-spec references say "rear-camera task N", "crash-response task N", or "MVP task N".
The demo-mode spec (another branch) is referenced by name only.

## Conventions

- `(test-first)` — write failing unit tests from the referenced acceptance criteria, then implement until
  green (the existing `.kiro/hooks/test-first-before-task.json` applies).
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers (`rear-camera N`, `crash-response N` for other specs).
- `_Parallel:_` names the parallel group (see "Parallel groups") or says what can run alongside.
- Each task is one reviewable commit or small PR. **Commits are made by the owner**, never by an
  automated agent unless asked.
- **Owner tags:** `[iOS]` iOS app owner · `[Role C]` backend/data owner (also author of the spike) ·
  `[Owner]` product decision / hardware. `[Teammate B]` has no tasks in this spec.
- **Priority tags:** `[DEMO]` blocks the live demo · `[IMPORTANT]` expected but the demo can run without
  it · `[STRETCH]` valuable, never blocking · `[FUTURE]` documented follow-up.
- Pure logic lives in `Packages/WhooshWire` (run `swift test --package-path Packages/WhooshWire`) or in
  the app's `Metrics/` (run `scripts/test.sh`). Run the relevant suite before marking a task done. Tasks
  touching WatchConnectivity, HealthKit workout sessions, WatchKit haptics, background behavior,
  notifications, battery, or latency also need the **device check** named in the task (the owner's Apple
  Watch SE and the iPhone 14) and an entry in `manual-qa.md` (task 28).
- Layering is enforced by `scripts/privacy-check.sh` (task 2). New folders: `Packages/WhooshWire/`,
  `WhooshWatch/`, `Whoosh/Features/Watch/`; existing `Whoosh/Services/Remote/` and `Services/Alerts/` grow.
- **Copy rule for every task:** user-facing text says the rear-vehicle cue is experimental and that
  Whoosh cannot guarantee detection or delivery; it never claims prevention, prediction, help coming, or
  that emergency services were contacted. Phrase any disclaimer so it passes `scripts/privacy-check.sh`
  (for example "cannot guarantee detection or delivery").
- **No Swift is written by this spec's authoring job.** All code below is future work.

## Cross-spec dependencies (read before scheduling)

| This spec needs | From | Used by tasks |
| --------------- | ---- | ------------- |
| `RideStatus`, `RideRemoteCommand`, `AlertKind` additions, `RideCameraTuning` models | rear-camera task 2 | 6, 10, 13 |
| `AlertRoutingPolicy`, `StatusThrottle` (pure) | rear-camera task 10 | 9, 10 |
| `RideStatusPublisher`, `RideRemoteControlling`, `RideRemoteBridge`, `AlertSink`, `FanOutAlertManager`, `FakeRideRemote` | rear-camera task 13 | 13, 14 |
| `CameraRecordingCoordinator` / `RideCameraBridge` (camera state, save clip) | rear-camera tasks 16, 19 | 13, 24 |
| Ride mode, screen controller | rear-camera task 21 | 23 |
| Mount & frame, readiness checklist | rear-camera tasks 9, 22 | 22, 23 |
| Interruption / "camera paused" handling | rear-camera task 25 | 24 |
| Phone audio / notification sinks | rear-camera task 29 (and the demo-mode spec's `HapticAudioAlertManager`) | 14, 24 |
| Crash integration (forced un-dim, wrist cancel hook) | rear-camera task 30 | 21 |
| `CrashResponseCoordinator` (rider cancel), countdown host | crash-response tasks 12, 20 | 13, 21 |
| Forced rear-vehicle alert and crash drill | the demo-mode spec (by name) | 26 |

Where an upstream task is not merged yet, build against its protocol with the fake; nothing here needs
the real upstream implementation until the device integration tasks (21, 23, 24, 28).

## Demo tiers

| Tier | What the judges see | Needs | Tasks |
| ---- | ------------------- | ----- | ----- |
| **Tier 0 — "It buzzes"** (no ride needed) | Phone **Apple Watch** screen shows the checklist → "Send test buzz" → the wrist buzzes and the rider confirms → "Feel the patterns" plays each pattern → with demo mode, **Simulate approaching vehicle** buzzes the wrist, labeled DEMO. Works in airplane mode. Also works in fallback F2 (watch app on screen). | spike go + tasks 3–5, 8, 9, 12, 14–17, 19, 22, 26 | 0–5, 8, 9, 12, 14, 15, 16, 17, 19, 22, 26 |
| **Tier 1 — "It controls"** | Start a ride on the phone; the watch starts its workout session; wrist-down, the rider glances: time / distance / speed and camera state; pause, resume, **Save clip**, hold-to-stop; camera trouble buzzes. | Tier 0 + 6, 10, 11, 13, 18, 20, 24 | + 6, 10, 11, 13, 18, 20, 24, 25 |
| **Tier 2 — "It protects"** | Crash **drill** from demo mode: the wrist shows "DEMO — NOT REAL" countdown with a large **I'm OK — Cancel**; cancel is confirmed by the phone's reply; start the ride **from the wrist** after the phone is armed; kill the link and show the honest "iPhone not responding" and the audio announcement. | Tier 1 + 7, 21, 23, 27 | + 7, 21, 23, 27 |

If the watch misbehaves on demo day the phone's audio path (rear-camera) and the ride itself are
unaffected (Never block a ride).

---

## Phase 0 — Gate and feasibility

- [x] 0. `[Owner]` `[DEMO]` Review and approve the spec; resolve open decisions; identify the watch
  - Read `requirements.md`, `design.md`, and this plan. Decide **O-W1 … O-W11** or accept the recommended
    defaults, and record answers in `design.md` "Owner resolution".
  - **Identify the Apple Watch SE** (Watch app → General → About, or Apple Support "Identify your Apple
    Watch model"): generation, size (40/44 mm), watchOS version; confirm a paired iPhone 14.
  - Review the seam amendments A1–A11 against the approved rear-camera and crash-response specs, and
    reconcile with the demo-mode spec (forced alert and drill flow through the fan-out; `isDemo` on
    `AlertContext`).
  - _Verify:_ spec status changed to "Approved"; open decisions marked resolved; watch model recorded.
  - _Requirements:_ 1.9, 2.1, 2.2, 21.5
  - _Parallel:_ none (gate)

- [ ] 1. `[Owner]` + `[iOS]` `[DEMO]` **Feasibility spike — go / no-go**
  - Work in a **new folder** `spikes/watch-link/` (copy of the needed files); leave `spikes/watch-haptics/`
    exactly as Role C wrote it. First goal: make the existing prototype compile and run on the paired
    iPhone 14 and Apple Watch (it has never been compiled; expect API-name fixes). Use the spike's setup
    notes (HealthKit capability and usage strings on the watch target, Swift Language Mode 5 for the spike
    only).
  - Run the spike's tests **T1–T8** (feel; phone→watch with app on screen; wrist down without a workout;
    wrist down with a workout; phone in the foreground screen-on; mirrored-notification baseline;
    connection loss; 30-minute battery) and add **T9–T14**:
    - **T9** force-quit and system-terminated phone app: does a watch `sendMessage` reach or relaunch it?
    - **T10** `startWatchApp` from the phone: time to session running with the watch on the wrist, dim,
      locked, charging; whether the iPhone target needs the HealthKit capability or authorization.
    - **T11** paused workout session: app still alive, reachable, haptics allowed?
    - **T12** workout location type `.unknown` vs `.outdoor`: GPS indicator and battery; background
      reliability.
    - **T13** mirrored-workout data channel: round trip and reliability (for fallback F1).
    - **T14** Silent Mode, Theater Mode, Do Not Disturb, Water Lock, Low Power Mode, and haptic strength:
      effect on `play(_:)`; also whether the Audio background mode is required for background haptics
      (build with and without).
  - Repeat each test at least 5 times and report "x of 5"; for latency collect at least 50 round-trip
    samples per condition (watch app on screen; wrist down with a workout; phone screen on in a ride-mode
    look-alike; phone locked with background location).
  - Write results to `.kiro/specs/watch-companion/spike-results.md` and fill the design's "Measured
    results"; apply the **go criteria** in `design.md` ("Fallback ladder") and record the decision: **F0
    go**, or fall back to **F1** (mirrored channel), **F2** (foreground-only), or **F3** (no watch). Confirm
    or change O-W2, O-W4, O-W10, and the minimum background modes (Workout processing; Audio or not).
  - _Verify:_ results table filled with conditions and sample counts; decision recorded; no production
    code written.
  - _Requirements:_ 4.1, 4.4, 4.6, 4.10, 10.2, 21.4, 22.2
  - _Depends on:_ 0 (watch model known)
  - _Parallel:_ Group P0 (can run while pure-core tasks start, but no task 15+ begins before the decision)
  - _Note:_ Role C wrote the original spike and may help interpret its README (task C-W1).

- [ ] 2. `[iOS]` `[DEMO]` Steering, privacy script, and amendment notes
  - Update `scripts/privacy-check.sh` per `design.md` "Privacy": scan `WhooshWatch/` and
    `Packages/WhooshWire/Sources` too; WatchConnectivity only in `Whoosh/Services/Remote/WCSessionWireLink.swift`
    and `WhooshWatch/Services/Link/`; HealthKit / `HKWorkoutSession` only in `WhooshWatch/Services/Workout/`
    and the one phone file that calls `startWatchApp`; WatchKit haptic calls only in
    `WhooshWatch/Services/Haptics/`; the package, `Models`, and `Metrics` Foundation-only; `WhooshWatch/`
    imports no CoreLocation / MapKit / AVFoundation / Photos / networking / analytics; network-layer
    folders do not reference wire types. Merge with the pending rear-camera task 1 and crash-response task 2
    rules (whichever lands later merges the others).
  - Update `.kiro/steering/privacy.md` (Apple Watch companion section, permission rows, wire privacy rule)
    and `.kiro/steering/tech.md` (watchOS rows, confined frameworks) with the text proposed in
    `design.md`; update the header comment of the script and the `privacy-guard-on-save` hook description.
  - Apply the **recorded amendment notes** to the approved specs (short notes only, no renumbering):
    rear-camera Req 13.2 (start via armed `requestStart`), its `RideRemoteCommand` / `RideStatus` /
    `AlertSink` / `AlertKind` / `ScreenModeStateMachine` additions (A1–A6), and a pointer from rear-camera
    task 34 to this spec; crash-response Risks and consent-copy note (A8, A9).
  - _Verify:_ run the script against temporary sample files under allowed and disallowed paths (for
    example `Packages/WhooshWire/Sources/…` importing `WatchConnectivity` flagged; `WhooshWatch/Services/Link/…`
    allowed; `WhooshWatch/Features/…` importing `HealthKit` flagged; `Services/Sync/…` referencing a wire
    type flagged); delete the samples; the full run on the current tree still prints OK.
  - _Requirements:_ 19.7, 19.9, 1.9
  - _Depends on:_ 0
  - _Parallel:_ Group P0 (before any watch or wire code lands)
  - _Note:_ edits `scripts/` and approved docs, which the spec-writing job did not touch.

- [ ] 3. `[iOS]` `[DEMO]` Project setup: shared package and watchOS target
  - Create `Packages/WhooshWire` (Package.swift, Foundation-only, Swift Testing, Swift 6 language mode)
    with one trivial passing test; add the package to both the iOS and watch targets.
  - Add the `WhooshWatch` target to `project.yml` (watchOS app, companion of the iOS app, bundle id
    `com.whoosh.app.watchkitapp`, `WKCompanionAppBundleIdentifier`, deployment target per O-W1, Swift 6,
    team `Z87CXCTTK6`); capabilities and keys: HealthKit, Background Modes (**Workout processing**; Audio
    only if task 1 says so), `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
    (purpose-specific; copy finalized in task 29), Time Sensitive notifications only when task 21 needs it.
    Add the HealthKit capability to the iOS target **only if** task 1 showed `startWatchApp` needs it.
  - Extend `scripts/test.sh` to also run `swift test --package-path Packages/WhooshWire`.
  - Owner runs `xcodegen generate` once; commit the regenerated project.
  - _Verify (device):_ the watch app installs from Xcode onto the owner's watch and shows a placeholder
    screen; the iOS app and `WhooshTests` still build and pass; `swift test` runs.
  - _Requirements:_ 2.1–2.8
  - _Depends on:_ 0, 1 (background modes), 2
  - _Parallel:_ Group P0b (unblocks everything that touches targets)
  - _Pending task 1 spike:_ the project setup landed ahead of the feasibility spike. O-W2 (cycling
    `HKWorkoutSession` keep-alive) is the owner-approved path, so the watch target declares HealthKit +
    the **Workout processing** background mode and the write-only workout usage strings now. The **Audio**
    background mode, the watch Time-Sensitive notification permission, and any HealthKit capability on the
    iOS target are intentionally NOT added yet — they are gated on the spike (T14 for background haptics /
    Audio mode; T10 for the iOS `startWatchApp` capability) and on task 21 (watch crash-cancel
    notification). Revisit this target's capabilities once task 1 records its go decision and the minimum
    background modes in `spike-results.md`.

## Phase 1 — Pure core (Foundation only, test-first)

- [ ] 4. `[iOS]` `[DEMO]` Wire models and tuning (package)
  - `WireEnvelope`, `WireVersion`, the DTOs in `design.md` (`WireRideStatus`, `WireAlert`, `WireCommand`,
    `WireCommandReply`, `WireWatchState`, `WireHello`, `WireSummary`, `WireAlertReceipt`) with their enums
    (including `unknown` cases), and `WatchTuning` holding every default and range in the design.
  - Value types are `Equatable`, `Codable`, `Sendable`; enums decode unknown values safely.
  - _Verify:_ models compile in the package and in both targets; tuning clamps every range.
  - _Requirements:_ 5.3, 5.6, 19.1
  - _Depends on:_ 3
  - _Parallel:_ Group P1 root (tasks 5–11 start once this lands)

- [ ] 5. `[iOS]` `[DEMO]` Codec, versioning, golden fixtures, and the privacy allowlist (test-first)
  - Deterministic encode/decode of envelope + payload, property-list-safe output, strict total decoding
    (typed errors, never a crash), version negotiation from `hello`, N−1 compatibility, unknown-field and
    unknown-enum handling, size budgets.
  - Golden fixtures for every message type checked into the package tests; **PR-1** allowlist test that
    fails on any field outside the allowlist or any string over the short-code limit.
  - Unit tests MC-1…10, CV-1…6, PR-1.
  - _Requirements:_ 5.3–5.6, 19.2, 21.6
  - _Depends on:_ 4
  - _Parallel:_ Group P1

- [x] 6. `[iOS]` `[DEMO]` `CommandDedupeCache` and `RemoteCommandReducer` (phone `Metrics/`, test-first)
  - The 29-row decision table in `design.md` as a pure function of (ride state, camera state, crash phase,
    arming state, settings, version, command, cache). Outcomes and effects are data; undefined cases are
    typed `ignored`/`rejected`, never errors. The cache keeps 5 minutes / 128 entries.
  - Inputs are plain value types (the reducer does not know the coordinators).
  - Unit tests RC-1…29, CD-1…6, including: stale ride id can never stop a new ride; cancel loses the tie to
    expiry and reports `tooLate`; duplicate id returns the cached reply.
  - _Requirements:_ 6.1–6.4, 6.10, 7.2–7.7
  - _Depends on:_ 4; rear-camera 2 (state/command models)
  - _Parallel:_ Group P1

- [x] 7. `[iOS]` `[IMPORTANT]` `StartArming` state machine (phone `Metrics/`, test-first)
  - The 12-row table: arm only by the rider's tap and only when preconditions pass; expiry (default 5
    minutes, 1–15), resign-active, crash event, authorization loss disarm; accepted `requestStart` →
    starting → consumed; phone Start while armed consumes.
  - Unit tests SA-1…12 with a controllable `Clock`.
  - _Requirements:_ 9.1–9.3
  - _Depends on:_ 4
  - _Parallel:_ Group P1

- [x] 8. `[iOS]` `[DEMO]` Haptic catalog, selector, limiter, and freshness (package, test-first)
  - `HapticCue` (the `WKHapticType` names), `HapticPattern` (cue + delay steps), `HapticPatternSelector`
    (the catalog table, level-2 selection rule, no navigation cues), `WristHapticLimiter` (minimum gap,
    tier preemption, per-kind cooldowns, storm backoff 3→6→12 s with 30 s reset, duplicate ids, demo and
    disabled gating), `AlertFreshness` (TTL per kind with skew tolerance, replay records never buzz).
  - Unit tests HP-1…6 (including signature uniqueness and ≥ 100 ms spacing), HL-1…10, AF-1…5 with a
    controllable clock.
  - _Requirements:_ 11.1–11.6, 11.9, 12.2–12.5, 12.7
  - _Depends on:_ 4
  - _Parallel:_ Group P1

- [x] 9. `[iOS]` `[DEMO]` Phone routing additions: `AlertContext`, watch channel, escalation (phone `Metrics/`, test-first)
  - Additive models: `AlertContext` (id, tier, TTL, demo flag, confidence, hint), `AlertTier`,
    `AlertKind.watchDisconnected` / `.watchReconnected`, `WatchChannelState`.
  - Extend the rear-camera `AlertRoutingPolicy` with the watch channel states and the routing table in
    `design.md` (watch first for `ready`; watch **and** audio for `degraded`; phone channels for
    `unavailable`; crash countdown on all channels; audio not concurrent with a confirmed watch cue unless
    enabled), plus `AlertOutcomeTracker` (pending → confirmed | escalated | expired; escalate at most once;
    never after TTL).
  - Unit tests FO-1…10 (every cell of the routing table; escalation timing with a test clock).
  - _Requirements:_ 12.1, 13.2–13.7, 13.9
  - _Depends on:_ 4, 8; rear-camera 10
  - _Parallel:_ Group P1b

- [x] 10. `[iOS]` `[DEMO]` Channel, readiness, transport, freshness, projector, and mapper (test-first)
  - `WatchChannelEvaluator` (link state + `WireWatchState` → channel state), `WatchReadinessEvaluator`
    (rows pass/warn/info), `StatusTransportPolicy` (live/context table), `StatusFreshness`,
    `ElapsedTimeProjector` (anchor + monotonic clock, frozen when paused, no wall-clock subtraction), and
    `WireMapper` (rear-camera `RideStatus` → `WireRideStatus`, rounding, banner/camera/reason codes,
    dropping every field outside the allowlist).
  - Unit tests WE-1…6, RR-1…8, TP-1…8, SF-1…5, EP-1…6, MAP-1…6.
  - _Requirements:_ 3.6, 3.9, 8.2, 8.5, 8.6, 10.4, 10.9, 19.1
  - _Depends on:_ 4; rear-camera 2 (mapper)
  - _Parallel:_ Group P1

- [x] 11. `[iOS]` `[DEMO]` Watch-side reducers (package, test-first)
  - `WatchRideReducer` (phases, seq/epoch handling, stale transitions, control enablement with reasons),
    `WatchCommandTracker` (spacing, pending, same-id retries at 0/2.5/5 s, TTL → "Not confirmed" and
    reconcile, link loss, the crash exception), `CrashCountdownModel` (relative remaining time,
    announcement schedule, haptic repeat schedule, cancelling → cancelled/tooLate/sending, drill label,
    retry each 1 s), `WorkoutSessionStateMachine` (the 19-row table), `WatchNoticeLog` (last 10, in memory).
  - Unit tests WR-1…n, WC-1…6, CT-1…8, WS-1…19.
  - _Requirements:_ 4.4, 4.8, 4.12, 6.5–6.9, 8.1, 8.4, 10.4, 14.3, 15.2, 15.4, 15.7, 15.10, 16.2, 20.5
  - _Depends on:_ 4, 8, 10
  - _Parallel:_ Group P1b

## Phase 2 — Seams, fakes, and integration without devices

- [x] 12. `[iOS]` `[DEMO]` `WireLink`, link state machine, fakes, and the loopback pair (package, test-first)
  - `WireLink` protocol (activate; reachability and state callbacks; live send with a typed result and
    reply; context update; queue transfer; receive callbacks), `WireLinkStateMachine` (17 rows),
    `FakeWireLink`, and `LoopbackWireLinkPair` connecting a phone-side and a watch-side fake with
    controllable delay, drop, duplicate, reorder, and unreachable windows.
  - Unit tests LS-1…17, LB-1…8.
  - _Requirements:_ 5.7–5.11, 10.10, 21.2
  - _Depends on:_ 4, 5
  - _Parallel:_ Group P2

- [x] 13. `[iOS]` `[DEMO]` `WatchRideRemote` and the remote bridge with fakes (test-first)
  - `WatchRideRemote` implementing the rear-camera `RideRemoteControlling`: publish via
    `StatusTransportPolicy`, receive commands → dedupe → `RemoteCommandReducer` → `RideRemoteBridge`
    effects → reply with a fresh status. Apply amendments A2–A4 (additive `RideStatus` fields, `commandId` /
    `rideId` / `holdConfirmed` / `crashEventId`, `AlertContext` and the outcome callback) in the phone
    models and the bridge. The ride engine is **not** modified.
  - Integration tests INT-1…6 over the loopback pair with `FakeRideRemote` pieces: pause/resume/stop/save
    clip/cancel crash end to end; stale ride id; duplicate command; reply lost then same-id retry; remote
    failure never changes ride state or GPS.
  - _Requirements:_ 7.1, 7.3–7.9, 6.1–6.6, 20.8
  - _Depends on:_ 5, 6, 10, 12; rear-camera 13
  - _Parallel:_ Group P2

- [x] 14. `[iOS]` `[DEMO]` `WatchAlertSink` and fan-out wiring (test-first)
  - `WatchAlertSink` (an `AlertSink`): encode the alert, send live with a reply, map the receipt to an
    outcome, never block, surface failures; register it with the rear-camera `FanOutAlertManager`; wire the
    escalation timers (watch acknowledgement timeout 1.5 s) through `AlertOutcomeTracker`; keep the
    existing phone audio, notification, and phone-haptic sinks and the unchanged `AlertManager` protocol;
    "Also play a sound" setting (default off).
  - Unit tests FO-style with `FakeAlertSink` and the loopback pair: confirmed cue does not escalate; no
    receipt escalates to audio exactly once; stale alerts never escalate; sink failure leaves other sinks and
    recording untouched.
  - _Requirements:_ 13.1–13.7, 1.4
  - _Depends on:_ 9, 12, 13; rear-camera 13
  - _Parallel:_ Group P2b

- [x] 15. `[iOS]` `[DEMO]` Watch app model with fakes (compiles in the watch target)
  - `WatchSessionModel` (`@Observable`) wiring `WireLink`, the codec, the reducers, `HapticPlaying`,
    `WorkoutSessionController`, and a `Clock`, all behind protocols with fakes; no WatchConnectivity,
    HealthKit, or WatchKit import in the model. Hello handshake, status application, alert handling through
    freshness → limiter → selector → player, receipts, `WireWatchState` reporting.
  - Unit tests through the loopback pair and fakes (package or `WhooshTests`): alert in → receipt out with
    the right result; status applied; command out → reply handled; cue counts recorded.
  - _Requirements:_ 1.7, 2.5, 5.9, 11.8, 12.3
  - _Depends on:_ 11, 12, 3
  - _Parallel:_ Group P2 (with 13); **no work here until task 1 returns a go decision**

## Phase 3 — Real implementations, UI, and device checks

- [x] 16. `[iOS]` `[DEMO]` Phone WatchConnectivity adapter and `WatchLauncher`
  - `WCSessionWireLink` (the only phone file importing WatchConnectivity): activation, re-activation after
    deactivation, delegate callbacks hopping to an explicit actor, live send with reply, context update,
    queue transfer (capped outstanding transfers; stale ones cancelled), reachability, installed/paired
    facts. `WatchLauncher` (the only phone file calling `HKHealthStore.startWatchApp`) with the retry
    backoff (3 × 15 s) and a fake. `NoopWatchLink` when the setting is off.
  - _Verify (device):_ activation on the iPhone 14; reachability transitions; a status reaches the watch
    app on screen; `startWatchApp` launches the watch app (latency recorded, T10); HealthKit capability
    added to the iOS target only if the check requires it. Log in `manual-qa.md`.
  - _Requirements:_ 5.1, 5.7, 5.8, 10.3, 3.10
  - _Depends on:_ 12, 3, 1
  - _Parallel:_ Group P3 (with 17)
  - _Pending task 1 spike:_ landed ahead of the on-device spike. Built for the approved **O-W2** path
    (cycling workout-session keep-alive, fallback-ladder rung **F0**): the phone adapter owns only
    WatchConnectivity (`Whoosh/Services/Remote/WCSessionWireLink.swift`, with `PhoneRemoteFactory`) and
    `WatchLauncher` owns the single `startWatchApp` HealthKit call. The iOS target does **not** declare the
    HealthKit capability yet — that is gated on the spike's **T10** result (whether `startWatchApp` needs
    it). Re-confirm the live/context/transfer split and the outstanding-transfer cap against the measured
    latency once the spike records its go decision in `spike-results.md`. The spike is still **pending**;
    nothing here runs on device until it confirms **O-W2**.

- [x] 17. `[iOS]` `[DEMO]` Watch WatchConnectivity adapter and background-task handling
  - `WCSessionWireLink` for the watch (`WhooshWatch/Services/Link/`): activation, companion-installed fact,
    reachability, live send/reply, context, queue receive, and **completion of every WatchConnectivity
    background task** (on handling, on state change, and when no content is pending).
  - _Verify (device):_ messages both ways; the app survives suspension and wake without crashing or
    exhausting its background budget; wrist-down behavior recorded (T3/T4 results). Log in `manual-qa.md`.
  - _Requirements:_ 5.1, 5.8, 10.2
  - _Depends on:_ 12, 3, 1
  - _Parallel:_ Group P3
  - _Pending task 1 spike:_ built for the approved **O-W2 / F0** path. The watch link lives only in
    `WhooshWatch/Services/Link/` (`WCSessionWireLink` + `WatchLinkFactory`/`WatchLinkConnectivity`), and
    `WhooshWatch/App/WatchAppDelegate` forwards each `WKWatchConnectivityRefreshBackgroundTask` to the link,
    which completes it once `hasContentPending` is false (on activation, context, and user-info receipt).
    Re-confirm the drain-then-complete timing against the spike's **T3/T4/T9** results in `spike-results.md`.
    The spike is still **pending**; nothing here runs on device until it confirms **O-W2**.

- [x] 18. `[iOS]` `[DEMO]` Keep-alive: `HKWorkoutSessionController`
  - The only HealthKit file on the watch: share-only authorization (workout type; read none) after an
    in-app explanation; create the cycling session and builder with the location type from O-W4; handle the
    workout-configuration entry point for `startWatchApp`; open-mid-ride auto-start; pause/resume per the
    ride (and the T11 outcome); stop → Save/Discard (default after 60 s); end on `errorAnotherWorkoutSessionStarted`;
    recover an active session on relaunch; orphan timeout (15 min); end early at 5% watch battery. Reports
    `WireWatchState`. Driven by `WorkoutSessionStateMachine`.
  - _Verify (device):_ the app keeps running and reachable with the wrist down; haptics allowed with the
    wrist down (spike T4 re-run on the production code); the session ends when the ride ends on the phone;
    saved/discarded workout behaves as chosen; another workout started on the watch is detected; battery
    sample M6. Log in `manual-qa.md`.
  - _Requirements:_ 4.1–4.12, 16.2, 16.3, 16.6, 19.5
  - _Depends on:_ 11, 15, 17, 1
  - _Parallel:_ Group P3b
  - _Pending task 1 spike:_ built for the approved **O-W2 / F0** path. `HKWorkoutSessionController`
    (the only HealthKit file on the watch) drives the pure `WorkoutSessionStateMachine`: share-only auth
    (`HKObjectType.workoutType()`, read `[]`), cycling session + live builder, retry-with-backoff, 60 s
    default-save timer, orphan/low-battery stop, `recoverActiveWorkoutSession`, and a diffed `WireWatchState`
    report; battery is read via `WKInterfaceDevice` (monitoring, not a haptic call). Two rows are left
    conservative pending the spike: **T11** (pause the session vs keep it running — change only the effect),
    and **O-W4** (`.outdoor` vs `.unknown` location type — change only the value). Depends on task 15's
    `WatchSessionModel` (not in this change) to be driven in-app; the protocol + fake here let it be wired.
    The spike is still **pending**; nothing here runs on device until it confirms **O-W2**.

- [x] 19. `[iOS]` `[DEMO]` `WKHapticPlayer`, pattern tuning, and the on-watch pattern preview
  - The only watch file calling `WKInterfaceDevice.play`: plays patterns in one cancellable serial task,
    checks the app state, reports `suppressedNotActive`; a hidden "Feel patterns" list on the watch for
    tuning. Run spike test **T1** (distinguish patterns wrist down, over a sleeve, on a rough road) and
    adjust the catalog table in `design.md` and `HapticPatternSelector` (finalizing **O-W6**).
  - _Verify (device):_ each catalog entry distinguishable; the three important patterns unmistakable; no
    pattern interferes with the next; battery effect of a haptic burst noted (M7). Log in `manual-qa.md`.
  - _Requirements:_ 11.1–11.9, 12.2
  - _Depends on:_ 8, 15
  - _Parallel:_ Group P3 (with 16–18)

- [x] 20. `[iOS]` `[DEMO]` Watch UI: Ride, Controls, Idle/Ready, Summary, Settings
  - Thin SwiftUI views over `WatchSessionModel`: Ride page (three numbers, chips), Controls page
    (pause/resume, Save clip, **hold-to-stop** with progress ring and VoiceOver action, disabled-with-reason
    states), Idle/Ready page (readiness line, start when armed), Summary page (Save to Health / Discard),
    small Settings page, reduced-luminance presentation, brand tokens. Pending/confirmed/not-confirmed
    command states and reply-based local haptics.
  - _Verify (device, 40 mm and 44 mm if available):_ layout fits (Cancel ≥ 80 pt in task 21); hold-to-stop
    reliability with sweaty/gloved fingers (drift tolerance); controls disabled within 1 s on link loss;
    Dynamic Type; Always-On look if the watch has it. Log in `manual-qa.md`.
  - _Requirements:_ 6.7–6.9, 8.1, 8.3–8.8, 16.1, 16.4, 18.1–18.3, 18.7, 18.8
  - _Depends on:_ 11, 15, 18, 19
  - _Parallel:_ Group P3b

- [ ] 21. `[iOS]` `[IMPORTANT]` Crash countdown on the wrist
  - Phone: a read-only countdown snapshot from the crash coordinator and a rider-cancel that reports
    `cancelled` / `tooLate` / `notCancellable` (A8); publish countdown in status and send the `critical`
    alert; add the consent-copy sentence about the watch (A9); keep the phone's audible countdown and the
    rear-camera forced un-dim.
  - Watch: full-screen takeover (relative remaining time, count-only sentence, **I'm OK — Cancel** ≥ 80 pt,
    short disclaimer + "More", DEMO label for drills, Reduce Motion static), reply-confirmed outcomes,
    1 s retries with the queue copy of the cancel, phase display, and (per O-W8) the watch-local
    time-sensitive notification with a Cancel action as backup (request notification authorization lazily).
  - _Verify (device):_ drill from the demo-mode path: haptic pattern, takeover, cancel confirmed; cancel at
    the deadline reports `tooLate`; unreachable phone → retry text; notification action works while a
    workout runs with the screen off (Verify row 22); screen-off honesty note. Log in `manual-qa.md`.
  - _Requirements:_ 15.1–15.10, 7.6, 11.1
  - _Depends on:_ 11, 13, 20; crash-response 12, 20; rear-camera 30 (forced un-dim)
  - _Parallel:_ Group P4

- [x] 22. `[iOS]` `[DEMO]` Phone Apple Watch screen: readiness, haptics test, patterns, settings
  - `WatchReadinessView(+VM)` driven by `WatchReadinessEvaluator`: checklist rows with icon + text, the
    haptics test (send test alert; show the reply; "I felt it" / "I didn't"; troubleshooting after three
    misses), **Feel the patterns**, install/pair instructions, reminders, watch battery; Home entry and a
    link from the Start path when the watch is in use; Settings section ("Apple Watch alerts and controls"
    default on when detected; "Also play a sound" default off; diagnostics counts). No system permission
    prompt except the HealthKit case in Requirement 3.10 if task 1 required it.
  - Views are thin; previews use `FakeWireLink`; works in airplane mode.
  - _Verify (device):_ checklist matches reality (unpair/uninstall/airplane/other workout); test buzz
    round trip; pattern previews never start a countdown. Log in `manual-qa.md`.
  - _Requirements:_ 3.1–3.10, 1.8, 13.3
  - _Depends on:_ 10, 13, 14, 16; rear-camera 22 (Start path)
  - _Parallel:_ Group P3b

- [ ] 23. `[iOS]` `[IMPORTANT]` Start from the wrist
  - Phone: "Ready to ride — start from watch" on the readiness / Mount & frame path driving `StartArming`
    (idle timer off, optional dim, expiry, cancel); `requestStart` handled by the reducer and the start
    path with `startedFromWatch` (skip or shorten the mount grace); screen-mode rows for armed and
    started-from-watch (A6); the Start-control amendment (A1).
  - Watch: Idle page "Hold to start" (0.8 s) enabled only when `armed`; typed rejection reasons rendered as
    short instructions; the keep-alive session starts on `recording`.
  - _Verify (device):_ arm → mount → start from the wrist → camera and ride mode begin; expiry and cancel
    disarm; a watch can never arm; not-foreground phone cannot be started; a started-from-wrist ride looks
    identical in storage and summary. Log in `manual-qa.md`.
  - _Requirements:_ 9.1–9.8
  - _Depends on:_ 7, 13, 20, 22; rear-camera 21, 22
  - _Parallel:_ Group P4

- [ ] 24. `[iOS]` `[IMPORTANT]` Notices end to end
  - Map the rear-camera events to wire alerts (clip saved/not saved, camera interrupted/resumed/stopped
    with reason, phone battery low at 20% and 8%), the watch-originated link lost/restored cues, the watch
    battery report, the Notices page with unread badge, `replay` records via the queue channel, reminders
    (≤ once per minute per reason, ≤ 2), acknowledgement, and the audio-only phone announcements
    ("Watch disconnected").
  - _Verify (device):_ interrupt the camera by locking the phone mid-ride → watch buzzes and logs;
    camera stopped by a forced low-storage fake → buzz + chip; battery notices; reconnect shows past notices
    without re-buzzing. Log in `manual-qa.md`.
  - _Requirements:_ 14.1–14.7, 10.5
  - _Depends on:_ 14, 20; rear-camera 25, 29
  - _Parallel:_ Group P4

- [ ] 25. `[iOS]` `[IMPORTANT]` Reconnect, staleness, and orphan handling
  - Hello replays on reachability change; full status + active countdown + unread notices on reconnect;
    stale presentation after 15 s (display active) with "est." elapsed and disabled controls; "iPhone app may
    have closed" after 60 s; orphan session timeout (15 min); epoch reset on a new ride; `startWatchApp`
    rescue when the phone sees `installedUnreachable` during a ride.
  - _Verify (device):_ matrix rows 4–8 from `design.md` exercised and recorded: airplane toggle mid-ride,
    walking out of range, killing the phone app mid-ride, force-quit before a ride, watch app killed mid-ride.
    Log in `manual-qa.md`.
  - _Requirements:_ 10.1–10.10, 4.9, 20.1–20.3
  - _Depends on:_ 13, 16, 17, 18
  - _Parallel:_ Group P4

- [ ] 26. `[iOS]` `[IMPORTANT]` Demo-mode coordination
  - Confirm with the demo-mode spec (by name): the forced rear-vehicle alert and the crash drill reach the
    wrist through the same fan-out, carry `AlertContext.isDemo`, and are labeled DEMO on the watch (which
    honors them only while the phone reports demo mode active); the auto-trigger exercises the limiter;
    no new demo-only path or wire message. Implement only iOS-side glue not owned by that spec (A11).
  - _Verify (device):_ Simulate approaching vehicle (single and auto every 10 s) → wrist cues at the
    limiter's pace; Simulate crash → DEMO takeover; turning demo mode off clears demo handling.
  - _Requirements:_ 12.6, 21.5, 15.3
  - _Depends on:_ 14, 21 and the demo-mode spec's tasks
  - _Parallel:_ coordination task; no code until both specs are approved

- [ ] 27. `[iOS]` `[IMPORTANT]` Accessibility pass (watch and phone screens)
  - VoiceOver labels, traits, and the Stop custom action; announcements for state changes and the
    countdown schedule; Dynamic Type; Reduce Motion; large targets; check on a real watch with VoiceOver on.
  - _Requirements:_ 18.1–18.8, 15.10
  - _Depends on:_ 20, 21
  - _Parallel:_ Group P5

- [ ] 28. `[iOS]` `[DEMO]` Device QA, budgets, and the measurement protocol
  - Create `.kiro/specs/watch-companion/manual-qa.md` (checklist from the design's manual list, spike T1–T14
    follow-ups, and every task's device check) and run it on the owner's watch and the iPhone 14; execute
    **M1–M10** and fill "Measured results" in `design.md`; adjust defaults (heartbeats, TTLs, acknowledgement
    timeout, hold drift tolerance, battery thresholds) from real numbers; re-measure the phone's budgets once
    with the watch attached.
  - _Requirements:_ 21.3, 21.8, 22.1–22.6, 10.10
  - _Depends on:_ 16–20 (and 21, 23, 24, 25 for their rows)
  - _Parallel:_ rolling; start with 16/17 and finish last

- [ ] 29. `[iOS]` `[IMPORTANT]` Privacy, permissions, and App Review pass
  - Finalize permission strings (HealthKit share; notifications on the watch if used) and confirm whether
    the share key is required with an empty read set; run the allowlist test and the privacy script over
    `Whoosh/`, `WhooshWatch/`, and the package; confirm the watch makes no network request; draft the App
    Review note for the workout-session use (clear in-app indication, Save/Discard, write-only workout
    type, purpose of the keep-alive); verify copy on every watch and phone screen against the honesty rules.
  - _Requirements:_ 19.1–19.10, 4.7, 16.3
  - _Depends on:_ 2, 18, 20, 22
  - _Parallel:_ Group P5

## Phase 4 — Stretch and future (never block the demo)

- [ ] 30. `[iOS]` `[STRETCH]` Complication / Smart Stack (opt-in, timer and state only)
  - WidgetKit complication with an anchor-driven system timer and a state glyph, deep link into the app,
    shared record written by the watch app, timeline reloads on state change; "Show ride on the watch face"
    setting (default off); no distance, speed, location, or crash data.
  - _Requirements:_ 17.1–17.5
  - _Depends on:_ 20

- [ ] 31. `[iOS]` `[STRETCH]` Mirrored-workout data channel behind `WireLink` (fallback F1)
  - Only if task 1 selects F1: implement a `WireLink` over `startMirroringToCompanionDevice` /
    `sendToRemoteWorkoutSession`, behind the same wire contract and tests; WatchConnectivity remains for
    context and queue items.
  - _Requirements:_ 5.1, 23.3
  - _Depends on:_ 12, 18, 1

- [ ] 32. `[iOS]` `[STRETCH]` Digital Crown confirm for Stop
  - An alternative to the timed hold ("Stop with Crown") for wet or gloved use; same `holdConfirmed` semantics.
  - _Requirements:_ 6.7, 18.6
  - _Depends on:_ 20

- [ ] 33. `[iOS]` `[FUTURE]` External Bluetooth haptic device sink (vibration proposal option D)
  - An `ExternalHapticSink` for a handlebar or glove device as another channel in the fan-out, with its own
    Bluetooth permission and background-mode decision then; no change to the wire contract.
  - _Requirements:_ 13.8, 23.2
  - _Depends on:_ 14 and a hardware decision

- [ ] 34. `[iOS]` `[FUTURE]` Newer-hardware gestures and directional hints
  - Optional double-tap Cancel on watches that support it (availability-gated); directional haptic hints
    from the detector's position hint if a meaning that does not collide with navigation cues is found.
  - _Requirements:_ 23.4, 23.5
  - _Depends on:_ 21 and measured detector data

---

## Role C tasks (`[Role C]`)

- [ ] C-W1. `[Role C]` `[IMPORTANT]` Spike support and review
  - Review this spec's use of `spikes/watch-haptics/`, share any prior hardware notes or results
    (including the WHOOP model finding), and help interpret the README's test protocol for task 1. Confirm
    **no schema, API, or backend change** is needed: the watch companion sends nothing to the database.
  - _Depends on:_ none (documentation); useful before task 1

---

## Parallel groups

| Group | Tasks | Notes |
| ----- | ----- | ----- |
| **P0** | 0, 1, 2 | Gate; spike and privacy script run in parallel after 0; nothing in P2+ starts before the spike decision |
| **P0b** | 3 | Needs the background-mode answer from 1 and the script from 2 |
| **P1** | 4 → then 5, 6, 7, 8, 10 in parallel | Distinct pure files; package vs `Metrics/` |
| **P1b** | 9, 11 | After their pure inputs (8; 8 + 10) |
| **P2** | 12, 13, 15 | 12 first; 13 needs rear-camera 13; 15 waits for the spike decision |
| **P2b** | 14 | After 9, 12, 13 |
| **P3** | 16 + 17 + 19 (one device session), 18 | WatchConnectivity adapters and haptic player independent; 18 needs 17 |
| **P3b** | 20, 22 | Watch UI and phone screen proceed on fakes while P3 is developed |
| **P4** | 21, 23, 24, 25 | After the pieces they integrate |
| **P5** | 27, 29 | After the UI exists |
| **Rolling** | 28 | Starts with 16/17, ends last |
| **Role C** | C-W1 | Independent; helps task 1 |
| **Coordination** | 0, 1 (decision), 26 | Cross-spec and hardware agreements |

Two people can work in parallel with no merge pain: **the iOS owner** on the spike (task 1), project setup,
adapters, and device work; **a second contributor** on the pure core (tasks 4–11) and the watch UI against
fakes.

## Proposed order of implementation

1. **Gate:** 0 (decisions, watch model), then 1 (the spike) and 2 (privacy script and steering) in parallel.
   Role C offers notes (C-W1).
2. **Setup:** 3 (package and watch target), as soon as 1 answers the background modes.
3. **Pure core:** 4 → 5, 6, 7, 8, 10 in parallel → 9, 11.
4. **Seams and fakes:** 12 → 13 → 14; 15 once the spike is a go.
5. **Make it buzz (Tier 0):** 16, 17, 19, 22 (then 26 with the demo-mode spec).
6. **Make it control (Tier 1):** 18, 20, 24, 25.
7. **Make it protect (Tier 2):** 21, 23, 27.
8. **Prove it:** 28 rolling; 29 before the owner's final review.
9. **Extend:** 30–34 as time allows.

Critical path to the Tier 0 demo: 0, 1, 2, 3, 4, 5, 8, 9, 12, 14, 15, 16, 17, 19, 22, 26.
Critical path to Tier 1 adds 6, 10, 11, 13, 18, 20, 24, 25. Tier 2 adds 7, 21, 23, 27.

## Kiro hooks

- **Existing, still sufficient:** `privacy-guard-on-save` runs `scripts/privacy-check.sh` on every saved
  Swift file; after task 2 it enforces the watch, package, HealthKit, and WatchConnectivity rules.
  `run-tests-after-task` and `test-first-before-task` apply unchanged (task 3 makes `scripts/test.sh` run
  the package tests too).
- **Optional new hooks (not created in this job; add only if wanted):**
  - `wire-contract-golden-guard` — after saving files in `Packages/WhooshWire/Sources/WhooshWire/Wire/`,
    run only the codec and fixture tests.
  - `spike-decision-reminder` — `PreTaskExec` reminder for tasks 15–25 that the spike decision and the
    chosen fallback rung (`spike-results.md`) must be read first.
  - `watch-hot-path-reminder` — reminder for tasks 17–19 that nothing on the watch may do per-second heavy
    work or call `play(_:)` outside the player.

## Definition of done (per task)

1. Code matches the layering table: the package stays Foundation-only; WatchConnectivity, HealthKit, and
   WatchKit haptic calls appear only in their named files; framework access is behind a protocol with a
   fake.
2. New or changed logic has unit tests from the referenced acceptance criteria; the relevant suites are
   green (`swift test --package-path Packages/WhooshWire` and `scripts/test.sh`).
3. The device verification named in the task is done on the owner's watch and iPhone 14 and logged in
   `manual-qa.md`; numbers are recorded in `design.md` "Measured results" where the task measures.
4. No new first-party compiler warnings; Swift 6 language mode on the watch target.
5. Privacy invariants intact: nothing in the wire outside the allowlist; no network in the watch target;
   permissions requested only at the moment of use; honest copy passing `scripts/privacy-check.sh`.
6. A watch or link failure never changes ride state, GPS points, or camera recording (assert in a test
   where the task touches the remote bridge or the sinks).
7. Phone-authoritative: no watch code decides a ride, camera, or crash state transition.
8. Failure is never silent: the relevant announcement path (watch, audio, notification, summary note) is
   exercised in a test or a QA row.

## Traceability (requirement → tasks)

| Req | Tasks |
| --- | ----- |
| 1 Scope and non-goals | 0, 2, 13, 14, 15, 22 |
| 2 Targets and structure | 0, 3 |
| 3 Pairing and readiness screen | 10, 16, 22 |
| 4 Keep-alive | 1, 11, 18, 25 |
| 5 Channels and wire contract | 4, 5, 12, 16, 17, 31 |
| 6 Wrist commands | 6, 11, 13, 20, 32 |
| 7 Phone-side command handling | 6, 13, 21 |
| 8 Live status | 10, 11, 13, 20 |
| 9 Start from the wrist | 7, 23 |
| 10 Phone not running; reconnect | 1, 10, 11, 12, 16, 17, 24, 25, 28 |
| 11 Haptic catalog | 8, 15, 19, 21, 24 |
| 12 Rate limiting | 8, 9, 14, 15, 19, 26 |
| 13 Fan-out and sinks | 9, 14, 22, 33 |
| 14 Notices | 11, 24 |
| 15 Crash countdown on the wrist | 11, 21, 26, 27 |
| 16 End of ride and Health | 11, 18, 20, 29 |
| 17 Complications | 30 |
| 18 Accessibility | 20, 27, 32 |
| 19 Privacy | 2, 4, 5, 10, 18, 29 |
| 20 Resilience | 11, 13, 18, 25 |
| 21 Testing and QA | 1, 5, 12, 15, 26, 28 |
| 22 Budgets | 1, 28 |
| 23 Future seams | 31, 33, 34 |
