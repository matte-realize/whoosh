# Design — Whoosh Apple Watch Companion

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O-W1–O-W11 (`design.md`, "Owner resolution"). Owner's watch: Apple Watch SE (2nd generation). This document contains **no source
code** by design: the owner requires requirements, design, and tasks to be reviewed before any
implementation. Types, protocols, and state machines are described in tables and diagrams; code is
written later, task by task, test-first (`tasks.md`), and only after the feasibility spike (task 1)
returns a **go**.

## Overview

The phone is rear-mounted and unreachable (rear-camera spec). The wrist becomes the only in-ride
surface. The watch app is deliberately **thin and phone-authoritative**: it shows what the phone
publishes, sends typed commands, plays haptics, and keeps itself alive with a cycling workout
session. All decisions that matter (ride state, camera state, crash workflow) stay on the phone,
behind the state machines that already exist.

```
 iPhone (authoritative)                                         Apple Watch (remote + display + actuator)
 ┌────────────────────────────────────────────────────┐        ┌───────────────────────────────────────────┐
 │ RideSessionViewModel ◀── RideRemoteBridge ◀── RemoteCommandReducer ◀─┐                                  │
 │ CameraRecordingCoordinator / ClipPinner                              │   commands (live, reply)          │
 │ CrashResponseCoordinator (riderCancel)                               │ ◀──────────────────────────────── │ WatchCommandTracker ◀ UI intents
 │                                                                      │                                   │
 │ RideStatusPublisher ─▶ StatusTransportPolicy ─▶ WatchRideRemote ─────┼─ status (live | context) ───────▶ │ WatchRideReducer ─▶ SwiftUI pages
 │ FanOutAlertManager ─▶ AlertRoutingPolicy ─▶ WatchAlertSink ──────────┼─ alert (live, ack) ─────────────▶ │ AlertFreshness ▶ WristHapticLimiter
 │      │   └▶ PhoneAudioAlertSink / LocalNotificationSink / (future ExternalHapticSink)                      │            ▶ HapticPatternSelector
 │ StartArming ─ WatchLauncher (startWatchApp)                          │   hello / watchState / receipts    │            ▶ HapticPlaying (WKInterfaceDevice)
 │ WatchChannelEvaluator ◀── WireLink (WCSessionWireLink)  ◀════ WatchConnectivity ════▶ WireLink (WCSessionWireLink) │ WorkoutSessionController (HKWorkoutSession)
 └────────────────────────────────────────────────────┘        └───────────────────────────────────────────┘
          Packages/WhooshWire (Foundation-only): envelope · codec · DTOs · versioning · pure watch-side logic · WireLink protocol · fakes
```

### Revisability note

WatchConnectivity, HealthKit workout sessions, WatchKit haptics, and watch notifications are each
behind a protocol with a fake. All numeric values are tuning defaults in one `WatchTuning` type and
are **hypotheses to be measured** on the owner's watch and the iPhone 14 (tagged *(verify)*). Items
marked **OPEN** need an owner decision.

---

## Changed assumptions — reasoning (W-A … W-G)

The one-line table is in `requirements.md`. This section records the consequences.

### W-A. Start from the wrist is armed, not free

The rear-camera spec excluded a remote start because a ride started without framing is the likeliest
cause of useless footage, and because iOS needs the foreground for the camera and for starting
When-In-Use location updates. Both facts remain. What changes is the rider's real flow: frame the
camera, **mount the phone, walk to the front of the bike, start from the wrist**. The phone is already
in the foreground and framed; the only missing piece is a way to tell the phone "now". The answer is an
explicit **armed** state set by the rider's own tap on the phone (so a stray watch tap can never start
a ride on a phone in a bag) and expiring on its own. See "Start from the wrist".

### W-B. The watch must stay alive, and Apple gives exactly one tool for cycling

Capability rows 3–8 below establish that a normal watch app is suspended when the wrist drops, that
`sendMessage` from the iPhone does not wake the watch app, and that haptics have no effect in the
background **except for apps with an active workout session**. Extended runtime sessions do not offer a
cycling type. So the watch holds a cycling `HKWorkoutSession` for the ride. This is the design's central
bet; the spike gates it.

### W-C … W-G

See `requirements.md`. In short: the watch companion is now specified (opt-in, post-MVP); HealthKit
appears on the watch only as write-only workout sharing; the crash countdown gains a wrist cancel;
`AlertSink` gains outcomes so the fan-out can escalate; and a ready watch becomes the primary route for
camera notices (the notification becomes the escalation).

---

## Platform capability investigation

**Method and honesty note.** On October 24, 2026 the Apple pages marked **Checked** were fetched from
`developer.apple.com` (their Markdown versions) and `support.apple.com`. Pages: *Apple Watch and iPhone
compatibility* (support 118490), *Notifications on your Apple Watch* (support 108369), `WCSession`
(`isReachable`, `sendMessage`, `updateApplicationContext`, `transferUserInfo`), *Transferring data with
Watch Connectivity* (sample), *Using extended runtime sessions*, `WKExtendedRuntimeSession`,
`WKHapticType`, `WKInterfaceDevice.play(_:)`, *Running workout sessions*, `HKWorkoutSession`,
`startMirroringToCompanionDevice`, and `HKHealthStore.startWatchApp(with:completion:)`. Forum threads
are cited as **Forum** and are evidence of reports, not of current behavior. The spike
(`spikes/watch-haptics/`) has **never been compiled or run**, so none of its table is evidence. Items
tagged **Verify** MUST be confirmed on the owner's watch (task 1 or the named device check) before a
task relies on them. Nothing here is a promise about behavior on a specific watchOS release.

| # | Question | Finding | Status |
| - | -------- | ------- | ------ |
| 1 | Which watchOS versions do Apple Watch SE models run? | Apple's table (published September 17, 2026): **SE (1st generation): watchOS 7 to 10.6.1** (iPhone 6s or later, iOS 14 or later); **SE 2: watchOS 9 or later** (iPhone 8 or later); **SE 3: watchOS 26 or later** (iPhone 11 or later). The table gives a model's *minimum* for current models, so SE 2's upper bound is not stated there; one news report (Forum-grade, **MacRumors, June 2026**) says watchOS 27 drops SE 2. A **watchOS 10.0 deployment target runs on every SE generation.** | **Checked** (Apple table); SE 2 upper bound **Verify** |
| 2 | Which iPhone/iOS does watchOS 10 need? | The same table lists Series 9 and Ultra 2 as **iOS 17 or later ↔ watchOS 10 or later**, and says updating to watchOS 11 requires iOS 18. So watchOS 10 pairs with iOS 17, the app's minimum; the owner's iPhone 14 satisfies it. | **Checked** |
| 3 | Can an extended runtime session keep a cycling app alive? | **No.** Types are self care, mindfulness, physical therapy, smart alarm; "Select a session type based on the app's intended use"; for strenuous activity "consider using" a workout session. A Forum answer warns that other uses risk App Review rejection. Time limits: 10 min / 1 h / 1 h / 30 min. | **Checked** |
| 4 | Does a workout session keep the app running with the wrist down? | **Yes.** "Your app continues to run throughout the entire workout session, even when the user lowers their wrist"; the app reappears on wrist raise; "your app can alert the user using audio or haptic feedback while running in the background"; excessive background CPU can get it suspended. Requires the **Workout processing** background mode; Apple's page adds that an app that "plays audio or provides haptic feedback during the workout session" must add the **Audio** mode too. | **Checked** (docs); whether the Audio mode is truly required for haptics **Verify** |
| 5 | Can the app play haptics with the wrist down? | `WKInterfaceDevice.play(_:)` "has no effect when called while ... `background` or `inactive`. By default, you cannot play haptic feedback in the background. **The only exception are apps with an active workout session.**" Calling in quick succession stops the current cue and imposes a **minimum 100 ms** delay. **While gathering heart rate with HealthKit, the haptic engine pauses heart-rate collection.** Excessive haptics drain battery. | **Checked** |
| 6 | Which haptic values exist? | `WKHapticType`: notification, directionUp, directionDown, success, failure, retry, start, stop, click, navigationGenericManeuver, navigationLeftTurn, navigationRightTurn (plus two underwater cues). "Always use the defined haptic types for their intended purposes." There is no custom waveform API in this class. | **Checked** |
| 7 | When can the phone message the watch live? | `isReachable` (iOS app): "A paired and active Apple Watch is in range, the corresponding WatchKit extension is running, and the extension's `isReachable` is true." On the watch it is true when the iPhone is in range and the extension "is running in the foreground, or is running with a high priority in the background (for example, during a workout session ...)". | **Checked** |
| 8 | Who can wake whom? | `sendMessage`: "Calling this method from your WatchKit extension while it is active and running wakes up the corresponding iOS app in the background and makes it reachable. **Calling this method from your iOS app does not wake up the corresponding WatchKit extension.**" Unreachable counterpart → error handler; messages queue serially and deliver in order while reachable. | **Checked** |
| 9 | Behavior after the iPhone app is force-quit | Forum reports: works with the app on screen, intermittently in the background, "not at all when the app is completely closed". | **Forum**; **Verify** (task 1, test T9) |
| 10 | `updateApplicationContext` semantics | "Replaces the previous dictionary"; delivered "when the opportunity arises"; "may call when the counterpart is not currently reachable"; readable later from `receivedApplicationContext`. Suited to frequently updated state. | **Checked** |
| 11 | `transferUserInfo` semantics | Guaranteed delivery; queued and delivered in order; continues if the app is suspended; **the Simulator does not support it**. | **Checked** |
| 12 | Watch background tasks | Every `WKWatchConnectivityRefreshBackgroundTask` must be completed or the budget runs out and the app can crash; complete on handling, on session state change, or when `hasContentPending` is false. | **Checked** (Apple sample) |
| 13 | Complication updates from the phone | `transferCurrentComplicationUserInfo`: **50 per day**; the watch app writes shared storage and reloads timelines. | **Checked** (Apple sample) |
| 14 | Starting the watch app from the phone | `HKHealthStore.startWatchApp(with:completion:)` (iOS) "launches or wakes the companion watchOS app to create a new workout session"; the system then calls the watch delegate's workout-configuration handler. Forum (2017): the handler may not run until the watch is woken, "30–60 seconds after the initial call". Whether the iPhone target needs the HealthKit capability or authorization for this call is not documented on that page. | **Checked** (API); latency and iPhone capability **Verify** (T10) |
| 15 | Mirrored workout (alternative channel) | `startMirroringToCompanionDevice`, `stopMirroringToCompanionDevice`, and `sendToRemoteWorkoutSession(data:)` exist on `HKWorkoutSession`; if the iOS app isn't running the system launches it in the background; the iOS app handles `workoutSessionMirroringStartHandler`. Latency and reliability unknown. | **Checked** (API exists); behavior **Verify** (T13) |
| 16 | Notification mirroring | "If your iPhone is unlocked, you get notifications on your iPhone instead of your Apple Watch"; if locked or asleep they go to the watch unless the watch is locked. Do Not Disturb or a locked watch sends them to the iPhone. Third-party notifications are delivered only if the paired iPhone is connected to a network. | **Checked** |
| 17 | One workout at a time | "Apple Watch runs one workout session at a time. If a second workout starts ... your delegate receives `errorAnotherWorkoutSessionStarted`, and your session ends." | **Checked** |
| 18 | Companion coordination guidance | If a workout starts in the iOS companion and the rider opens the watch app, the watch app "should automatically start a workout session for the workout in progress"; if started on the watch and ended on the iPhone, instruct the rider to end on the watch (we avoid it: the ride is phone-authoritative and ending it ends the session). The app "must clearly indicate when a workout session is in progress" and "either automatically save workout data ... or provide a clear option to explicitly save or discard". | **Checked** |
| 19 | Workout location type and GPS | "An outdoor cycling activity generates accurate location data, while an indoor cycling activity doesn't." Whether `.unknown` avoids GPS power is not stated. | **Checked** (outdoor/indoor); `.unknown` **Verify** (T12) |
| 20 | Does a *paused* workout session keep the app alive and haptics allowed? | Not documented on the pages read. | **Verify** (T11) |
| 21 | Haptics under Silent Mode, Theater Mode, Do Not Disturb, Water Lock, Low Power Mode, and "haptic strength" | Not documented for `play(_:)`. Water Lock disables touch. | **Verify** (T14) |
| 22 | Does a watch notification action execute while a workout is running with the screen off? | Not documented. | **Verify** (task 21) |
| 23 | Digital Crown and long-press gestures on watchOS 10 in SwiftUI | `LongPressGesture` / `onLongPressGesture`, `digitalCrownRotation` are established watchOS APIs; exact behavior with progress feedback and finger drift is to be checked. | **Verify** (task 20) |
| 24 | Double-tap gesture | A hand-gesture shortcut exists only on newer hardware and newer watchOS; **not** on SE (1st gen) or SE 2 and not relied on. | **Verify** (Future) |
| 25 | Watch display sizes | SE sizes are 40 mm and 44 mm; the design assumes roughly 162 × 197 pt and 184 × 224 pt and verifies that the 80 pt Cancel fits. | **Verify** (task 20) |
| 26 | `WCSession` message size and rate | No limits documented on the pages read; the design budgets ≤ 1 KB and ≤ 1 live status per 5 s. | **Verify** (T2) |
| 27 | HealthKit authorization on the phone for `startWatchApp` | Unknown whether `HKHealthStore` on iOS needs the capability and usage strings for this call. | **Verify** (T10) |
| 28 | App Review for workout-session use | Apple's page requires the app to clearly indicate the session and to save or discard; using a session only as a keep-alive is a possible review question. | **Verify** (task 29) |

### Spike learnings reused (and what is not)

`spikes/watch-haptics/` (Role C, October 24, 2026; README, `HapticMessage.swift`, `WatchReceiver.swift`,
`PhoneSender.swift`) is cited, **not edited**. What this design takes from it:

| # | Learning | Where used |
| - | -------- | ---------- |
| L1 | Cue names equal the `WKHapticType` cases; patterns are named data | `HapticCue` in the package (Requirement 11.5) |
| L2 | Strict dictionary parse that returns nil on bad input, with checks for empty / wrong-type / unknown values | Codec totality (Requirement 5.5) |
| L3 | Do not subtract phone and watch clocks; use round trips and each device's own clock | `ElapsedTimeProjector`, freshness (Requirement 8.2) |
| L4 | A reply that carries `workoutActive` lets the phone log whether the keep-alive was running | `WireWatchState`, alert reply fields |
| L5 | A session ended without a builder saves nothing to Health | Rejected for v1: Apple asks for save/discard (Requirement 16); we use the builder and discard explicitly |
| L6 | Repeat each test at least 5 times and report "x of 5" | Task 1 and task 28 reporting |
| L7 | The spike sets Swift Language Mode 5 to avoid strict-concurrency noise | Production uses Swift 6; adapters need an explicit actor boundary (risk) |
| L8 | `sessionDidDeactivate` must re-activate (iOS) | Link state row 5 |
| L9 | T3 (wrist down, no workout), T4 (wrist down, workout), T6 (notification baseline), T7 (connection loss), T8 (battery) | Task 1 repeats them and adds T9–T14 |
| L10 | The code was never compiled | Task 1 compiles it first; treat its APIs as unverified |

---

## Fallback ladder

If the spike or the device checks show the bet fails, the design degrades in this order. Each rung is a
complete, honest product; none changes the phone's ride behavior.

| Rung | Condition | Behavior |
| ---- | --------- | -------- |
| **F0** (target) | Workout session keeps the app reachable and haptic-capable with the wrist down | As specified |
| **F1** | Session works but WatchConnectivity is flaky or slow | Add the mirrored-workout data channel behind `WireLink` (O-W10); keep the same wire contract |
| **F2** | Haptics or reachability only work while the watch app is on screen | The watch is a **foreground readout and manual control**: controls usable on wrist raise; alerts go to phone audio; the watch says so in the readiness screen. No claim of wrist alerts |
| **F3** | No usable watch | Phone audio, ride-mode unlock gesture, the rear-camera fallback (its Req 13.8) |

**Proposed go criteria for task 1** (the owner decides): T4 (wrist down, workout running) buzzes **at
least 9 of 10** across two sessions; round-trip median ≤ 1 s with the phone screen on and in ride mode;
the cost measured by T8 is acceptable to the owner for the rides the owner actually takes. Anything less
selects F1 or F2.

---

## Architecture and layering

### Layering additions

| Layer / folder | Contents | Knows about | Must NOT import |
| -------------- | -------- | ----------- | --------------- |
| `Packages/WhooshWire` (Foundation-only, local Swift package, tests with `swift test`) | **Wire:** `WireEnvelope`, `WireCodec`, `WireVersion`, DTOs (`WireRideStatus`, `WireAlert`, `WireCommand`, `WireCommandReply`, `WireWatchState`, `WireHello`, `WireSummary`, `WireAlertReceipt`), `WatchTuning`. **Pure watch-side logic:** `HapticCue`, `HapticPattern`, `HapticPatternSelector`, `WristHapticLimiter`, `AlertFreshness`, `StatusFreshness`, `ElapsedTimeProjector`, `WatchRideReducer`, `WatchCommandTracker`, `CrashCountdownModel`, `WorkoutSessionStateMachine`, `WatchNoticeLog`, `WireLinkStateMachine`. **Seams:** `WireLink` protocol, `FakeWireLink`, `LoopbackWireLinkPair`, `WireClock` | Foundation | UIKit, SwiftUI, WatchKit, HealthKit, WatchConnectivity, CoreLocation, MapKit, AVFoundation, Photos, any networking API, the app targets |
| `Whoosh/Models/` (existing) | additive: `AlertKind` cases (`watchDisconnected`, `watchReconnected`), `AlertContext`, `AlertTier`, `WatchChannelState`, `StartReadiness`, `RemoteCommandOutcome` | Foundation | everything else |
| `Whoosh/Metrics/` (existing, pure) | `RemoteCommandReducer`, `CommandDedupeCache`, `StartArming`, `WatchChannelEvaluator`, `WatchReadinessEvaluator`, `StatusTransportPolicy`, `WireMapper` (domain ↔ wire), `AlertOutcomeTracker`, additions to `AlertRoutingPolicy` | Models, `WhooshWire` | UI, any framework |
| `Whoosh/Services/Remote/` (existing folder from rear-camera) | `WCSessionWireLink` (the **only** iPhone file importing WatchConnectivity), `WatchRideRemote` (a `RideRemoteControlling`), `WatchLauncher` (the **only** iPhone file calling `startWatchApp`), `NoopWatchLink` | Models, Metrics, `WhooshWire` | SwiftUI |
| `Whoosh/Services/Alerts/` (existing) | `WatchAlertSink` (an `AlertSink`; talks to `WireLink` through a narrow protocol, no WatchConnectivity import), `ExternalHapticSink` seam placeholder (Future) | Models, Metrics, `WhooshWire` | SwiftUI, WatchConnectivity |
| `Whoosh/Features/Watch/` (new) | `WatchReadinessView(+VM)`, `HapticPatternPreviewView`, `WatchSettingsSection`, `ReadyToRideView(+VM)` | ViewModels, Theme | WatchConnectivity, HealthKit, concrete services |
| `WhooshWatch/` (new watchOS target) | `App/` (entry, delegate), `Features/` (Ride, Controls, Idle, Notices, Countdown, Summary, Settings), `Services/Link/WCSessionWireLink`, `Services/Workout/HKWorkoutSessionController`, `Services/Haptics/WKHapticPlayer`, `Services/Notifications/CountdownNotificationScheduler`, `Support/Theme` | `WhooshWire` | CoreLocation, MapKit, AVFoundation, Photos, any networking API; business logic in views |
| `WhooshTests/` | phone-side tests, `FakeRideRemote` integration with the loopback link | | |
| `Packages/WhooshWire/Tests/` | all pure wire and watch-side tests, golden fixtures | | |

Dependency rule: identical to the MVP. Views → view models → service **protocols**; concrete types are
injected at the composition root (`AppEnvironment` on the phone, the watch app entry on the watch).

### Why a shared package

The wire contract is the one thing both apps must agree on exactly; compiling the same source in both
is the strongest guarantee. The package is Foundation-only, so it also compiles and tests on a Mac with
`swift test` in seconds, which keeps the watch logic out of simulator slowness and gives the
test-first loop a fast target. Alternative recorded as D-W4: put the same files in a synced `Shared/`
folder compiled into both targets and test them in `WhooshTests`; the package is recommended because it
cannot accidentally import UI frameworks.

### File layout (proposed)

```
Packages/WhooshWire/
  Package.swift
  Sources/WhooshWire/
    Wire/        WireEnvelope · WireCodec · WireVersion · WireRideStatus · WireAlert · WireCommand · WireCommandReply ·
                 WireWatchState · WireHello · WireSummary · WireAlertReceipt · WatchTuning
    Link/        WireLink · WireLinkStateMachine · FakeWireLink · LoopbackWireLinkPair · WireClock
    Haptics/     HapticCue · HapticPattern · HapticPatternSelector · WristHapticLimiter · AlertFreshness
    Watch/       WatchRideReducer · WatchCommandTracker · CrashCountdownModel · WorkoutSessionStateMachine ·
                 StatusFreshness · ElapsedTimeProjector · WatchNoticeLog
  Tests/WhooshWireTests/   codec · versions · fixtures · allowlist · patterns · limiter · reducers · state machines
Whoosh/
  Models/ Metrics/                    (additions listed above)
  Services/Remote/                    WCSessionWireLink · WatchRideRemote · WatchLauncher · NoopWatchLink
  Services/Alerts/                    WatchAlertSink (+ existing sinks from rear-camera)
  Features/Watch/                     readiness, patterns preview, settings, ready-to-ride
WhooshWatch/
  App/ · Features/{Ride,Controls,Idle,Notices,Countdown,Summary,Settings}/ · Services/{Link,Workout,Haptics,Notifications}/ · Support/Theme/
WhooshTests/
```

---

## The wire contract

### Envelope (every message)

| Key | Meaning |
| --- | ------- |
| `v` | Protocol version used for this message (integer) |
| `t` | Type name: `hello`, `status`, `alert`, `command`, `reply`, `watchState`, `receipt`, `summary` |
| `id` | Unique message id (UUID string); for `command` it is the `commandId`; for `alert` the alert id |
| `s` | Sender-session sequence number (integer, increases per sender launch) |
| `at` | Sender's wall-clock epoch seconds: **logs and coarse age estimate only**; never used for ordering or duration |
| `ttl` | Optional time-to-live in milliseconds |
| `p` | Payload: deterministic JSON `Data` (sorted keys); enums, numbers, booleans, ids only |

WatchConnectivity carries only property-list values; the dictionary above is property-list-safe, and the
payload is one `Data` blob so the JSON is identical on both sides and golden-testable.

### Versioning and negotiation

- `WireVersion.current` is 1; `minSupported` is 1. Each side's `hello` carries `[min, max]`, `appBuild`,
  a per-launch `sessionNonce`, and capability strings (for example `startFromWatch`, `crashCancel`,
  `haptics.v1`).
- The link uses `min(maxA, maxB)` if it is ≥ `max(minA, minB)`; otherwise the link is `incompatible` and the
  readiness screen says which side to update.
- A release must read the previous version. Within a version: only add fields; never repurpose or remove
  a field; unknown fields are ignored; enums decode unknown values to `unknown` (alert kinds `unknown`
  play the generic notice pattern with the text "Whoosh notice").
- A change that breaks the above bumps `current` and updates the golden fixtures in the same commit.

### Payloads (all values are enums, numbers, booleans, or ids)

**`WireRideStatus`** (phone → watch). Mapped from rear-camera's `RideStatus` by `WireMapper`.

| Field | Type / values | Notes |
| ----- | ------------- | ----- |
| `rideId`, `epoch` | UUID, integer | `epoch` increments per ride; resets watch state |
| `seq` | integer | monotonic within an epoch; older is ignored |
| `state` | `idle`, `recording`, `paused`, `signalLost`, `finished` | MVP `RideState` |
| `activeMs` | integer | active duration **at send**; the watch advances it with its own clock while `recording`/`signalLost` |
| `distance10m` | integer | distance in 10 m units (rounded) |
| `speedDms` | integer? | speed in 0.1 m/s units (rounded) or absent |
| `camera` | `{feature: off/on, state: off/preparing/recording/degraded/interrupted/stopped/failed, reason: code?}` | rear-camera `CameraRecordingState` and `CameraStopReason` codes |
| `flags` | set of `storageLow`, `phoneHot`, `lowPowerMode` | from rear-camera storage/thermal flags |
| `phone` | `{batteryPct: 0…100, charging: Bool}` | |
| `banner` | `none`, `signalLost`, `permissionRevoked`, `failed` | MVP `RideBanner` kinds as codes; no message text |
| `crash` | `{eventId, remainingMs, isDrill, contactCount, phase}`? | `phase`: `countdown`, `cancelled`, `sending`, `queuedOffline`, `sent`, `failed`, `stale`; absent when none. `remainingMs` is relative (skew-free) |
| `clip` | `{count, lastSavedAgoMs?}` | counts only |
| `start` | `notReady(reasonCodes)`, `ready`, `armed(untilMs)` | `untilMs` relative |
| `demo` | Bool | demo mode active (drills and demo alerts are honored only if true) |
| `watchEnabled` | Bool | the "Apple Watch alerts and controls" setting |

**`WireAlert`** (phone → watch): `alertId`, `kind`, `tier`, `level` (1 or 2 where relevant), `reason` (code),
`value` (for example battery percent), `isDemo`, `confidence` (0…10, coarse, optional), `hint` (`left`,
`center`, `right`, optional), `createdAgoMs`, `ttlMs`, `replay` (Bool: log only, do not buzz).
`kind` ∈ `rearVehicleCaution`, `cameraInterrupted`, `cameraResumed`, `cameraStopped`, `clipSaved`,
`clipNotSaved`, `phoneBatteryLow`, `crashCountdownStarted`, `crashCountdownEnded` (with `outcome`),
`hapticTest`, `patternPreview(patternName)`, `linkRestored`, `unknown`.

**`WireCommand`** (watch → phone): `commandId`, `kind` ∈ `pause`, `resume`, `saveClip`, `stop`,
`cancelCrashCountdown`, `requestStart`; `rideId?`; `holdConfirmed` (for `stop`/`requestStart`);
`crashEventId?`; `issuedAgoMs`; `attempt`.

**`WireCommandReply`** (phone → watch, in the reply handler): `commandId`, `outcome` ∈ `accepted`,
`alreadyInState`, `ignored(reason)`, `rejected(reason)`; `detail` (`saved`, `pending`, `nothingToSave`,
`storageFull`, `cameraOff`, `cancelled`, `tooLate`, `notCancellable`, `rideId` for start); `status`
(a `WireRideStatus`).
Reasons are an enum: `staleRide`, `noActiveRide`, `holdRequired`, `notArmed`, `notReady(code)`,
`rideActive`, `debounced`, `cameraNotRecording`, `noCountdown`, `staleEvent`, `unsupportedVersion`,
`unknownCommand`, `watchDisabled`.

**`WireWatchState`** (watch → phone): `session` ∈ `none`, `authorizing`, `preparing`, `running`, `paused`,
`stopping`, `failed(reason)`, `unavailable(reason)`; `healthAuthorized` (Bool/unknown); `appActive` (Bool);
`displayActive` (Bool); `batteryPct`; `lowPowerMode`; `hapticsArmed` (Bool); `anotherWorkout` (Bool);
`workoutSaved` (`none`, `saved`, `discarded`, `failed`).

**`WireAlertReceipt`** (watch → phone, normally the reply to an alert): `alertId`, `result` ∈ `played`,
`suppressedRate`, `suppressedStale`, `suppressedDuplicate`, `suppressedNotActive`, `suppressedDemo`,
`suppressedHigherTier`, `failed`; `workoutActive`; `playedAfterMs`.

**`WireSummary`** (phone → watch, queue): `rideId`, `durationMs`, `distance10m`, `avgSpeedDms`,
`cueCount`, `noticeCount`, `cameraGapCount`.

**`WireHello`**: see above, both directions.

### Channel assignment (normative)

| Message | Direction | Live (`sendMessage`) | Context (`updateApplicationContext`) | Queue (`transferUserInfo`) | If the counterpart is unreachable |
| ------- | --------- | -------------------- | ------------------------------------ | -------------------------- | --------------------------------- |
| `hello` | both | yes; the reply is the peer's hello | — | — | repeat on reachability change (max 3 tries per change) |
| `status` | phone → watch | when the watch display is active: on change + 5 s heartbeat | always the latest, at most 1 per 5 s (crash phase changes exempt); heartbeat 30 s when the display is off | — | context only; the watch marks stale |
| `alert` | phone → watch | yes, with reply (the receipt) | — | for must-arrive kinds (camera, battery, clip) as `replay` records so the log fills in | **never queued as a buzz**; the fan-out escalates |
| `command` | watch → phone | yes, with reply | — | **only** `cancelCrashCountdown` (guarded) | visible failure within 1 s; never silently queued |
| `reply` | phone → watch | the reply handler | — | — | lost reply → watch retries the same id; phone returns the cached reply |
| `watchState` | watch → phone | on change | latest | — | context |
| `receipt` | watch → phone | normally inside the alert reply | — | — | dropped (diagnostic) |
| `summary` | phone → watch | — | — | yes (ordered, must arrive) | queued |

Outstanding queue transfers are capped (default 20); stale ones are cancelled at ride end.

### Size and rate budgets *(verify, T2)*

Status ≤ 600 bytes of JSON; alert ≤ 300; command ≤ 300; reply ≤ 900 (it embeds a status); every message
≤ 1 KB. Live status at most one per second at the extreme (on change), normally one per 5 s.

---

## Link state machine (`WireLinkStateMachine`, pure; every row a unit test)

States: `unsupported`, `activating`, `notPaired` (phone only), `notInstalled`, `inactive`,
`installedUnreachable`, `reachable(helloPending)`, `ready(peer)`, `incompatible`.
Events: `activated(paired, installed)`, `activationFailed`, `deactivated`, `watchStateChanged(paired,
installed)`, `reachability(Bool)`, `helloReceived(peer)`, `helloTimeout`, `peerRelaunched(nonce)`.

| # | From | Event | Guard | To | Effects |
| - | ---- | ----- | ----- | -- | ------- |
| 1 | start | launch | not supported | unsupported | report; all sends become no-ops |
| 2 | start | launch | supported | activating | activate the session |
| 3 | activating | activated | phone ∧ not paired | notPaired | readiness explains |
| 4 | activating | activated | phone ∧ paired ∧ not installed (or watch ∧ companion missing) | notInstalled | readiness explains |
| 5 | activating, any active | deactivated / inactive | phone | inactive | re-activate (L8) |
| 6 | activating | activated | installed ∧ not reachable | installedUnreachable | start staleness timers |
| 7 | activating, installedUnreachable | reachability(true) / activated ∧ reachable | — | reachable(helloPending) | send `hello`; arm hello timeout |
| 8 | reachable(helloPending) | helloReceived | version ranges overlap | ready(peer) | negotiate; send full status (phone) / `watchState` (watch); resend active crash countdown |
| 9 | reachable(helloPending) | helloReceived | no overlap | incompatible | report which side must update; phone channels carry alerts |
| 10 | reachable(helloPending) | helloTimeout | tries < 3 | reachable(helloPending) | resend `hello` |
| 11 | reachable(helloPending) | helloTimeout | tries exhausted | installedUnreachable | mark "app not responding" |
| 12 | ready | reachability(false) | — | installedUnreachable | stale timers; announce after 20 s (Requirement 10.5) |
| 13 | ready | peerRelaunched | new nonce | ready | reset dedupe; resend status; resend countdown |
| 14 | notPaired, notInstalled | watchStateChanged | now installed | installedUnreachable | — |
| 15 | any | watchStateChanged | paired/installed lost | notPaired / notInstalled | channel `unavailable` |
| 16 | incompatible | helloReceived | overlap now | ready(peer) | — |
| 17 | any | undefined | — | same | no-op |

`WatchChannelEvaluator` (phone, pure) derives the routing availability from the link state **plus** the
watch's reported state:

| Channel state | Condition | Routing meaning |
| ------------- | --------- | --------------- |
| `unavailable` | setting off, not paired/installed, incompatible | phone channels only |
| `unreachable` | installed, not reachable | phone channels only; try `startWatchApp` during a ride (backoff) |
| `foregroundOnly` | reachable, but `session != running/paused` and the watch app is only active while on screen | **degraded**: watch + audio |
| `ready` | reachable ∧ (session running/paused) ∧ health authorized ∧ `hapticsArmed` ∧ not low battery | watch first; audio on timeout |
| `degraded(reason)` | ready minus one of: watch battery ≤ 15%, another workout, session failed, Health denied | watch + audio |

---

## Phone-side design

### `WatchRideRemote` and command handling

`WatchRideRemote` is a `RideRemoteControlling`: `publish(RideStatus)` maps to `WireRideStatus` and goes
through `StatusTransportPolicy`; incoming `command` envelopes are decoded, deduped, and handed to the
rear-camera `RideRemoteBridge`, whose effect execution calls only existing intents. Replies embed a fresh
status.

```
 command envelope ─▶ WireCodec.decode ─▶ CommandDedupeCache (hit → cached reply)
        ─▶ RemoteCommandReducer(state, cmd) ─▶ outcome + effects(data)
        ─▶ RideRemoteBridge executes effects on the main actor (pause/resume/stop · ClipPinner · riderCancel · start path)
        ─▶ reply(outcome, detail, status after) ─▶ cache + send
```

### `RemoteCommandReducer` — decision table (every row a unit test)

Inputs: ride state (MVP `RideState`), camera state, crash phase, arming state, settings, protocol
version, command. `rideId` is checked first for every command except `requestStart`.

| # | Command | Condition | Outcome | Effect |
| - | ------- | --------- | ------- | ------ |
| 1 | any | `commandId` in the dedupe cache | cached reply | none |
| 2 | any | version unsupported | `rejected(unsupportedVersion)` | none |
| 3 | any | "Apple Watch alerts and controls" off | `rejected(watchDisabled)` | none |
| 4 | not start | `rideId` ≠ active ride id | `ignored(staleRide)` | none |
| 5 | `pause` | `recording` or `signalLost` | `accepted` | `rideSession.pause()` |
| 6 | `pause` | `paused` | `alreadyInState` | none |
| 7 | `pause` | `idle` / `finished` | `ignored(noActiveRide)` | none |
| 8 | `resume` | `paused` | `accepted` | `rideSession.resume()` |
| 9 | `resume` | `recording` / `signalLost` | `alreadyInState` | none |
| 10 | `resume` | `idle` / `finished` | `ignored(noActiveRide)` | none |
| 11 | `stop` | active ∧ `holdConfirmed` | `accepted` | `rideSession.stop()`; ride mode restores before the summary |
| 12 | `stop` | active ∧ not `holdConfirmed` | `rejected(holdRequired)` | none |
| 13 | `stop` | `finished` | `alreadyInState` | none |
| 14 | `stop` | `idle` | `ignored(noActiveRide)` | none |
| 15 | `saveClip` | active ∧ camera `recording`/`degraded` ∧ not debounced ∧ room | `accepted` (+ `saved` or `pending`) | `ClipPinner.saveManual` |
| 16 | `saveClip` | within the 2 s debounce | `ignored(debounced)` + last result | none |
| 17 | `saveClip` | camera not recording | `rejected(cameraNotRecording)` (+ `cameraOff` / `nothingToSave`) | none |
| 18 | `saveClip` | pinned storage full | `rejected` (+ `storageFull`) | none |
| 19 | `saveClip` | no active ride | `ignored(noActiveRide)` | none |
| 20 | `cancelCrashCountdown` | crash `countdown` ∧ same `crashEventId` | `accepted` (+ `cancelled` or `tooLate`, read back after the call) | coordinator rider-cancel (never gated by consent) |
| 21 | `cancelCrashCountdown` | crash `queuedOffline` or retry-wait ∧ same id | `accepted` (+ `cancelled`) | rider-cancel (crash rows 17, 21) |
| 22 | `cancelCrashCountdown` | request in flight | `rejected` (+ `notCancellable`) | none (crash row 18) |
| 23 | `cancelCrashCountdown` | already sent / cancelled / resting | `alreadyInState` (+ `tooLate`) | none |
| 24 | `cancelCrashCountdown` | no countdown, or different id | `ignored(noCountdown` or `staleEvent)` | none |
| 25 | `requestStart` | armed ∧ idle ∧ all start guards | `accepted` (+ new `rideId`) | start path with `startedFromWatch` |
| 26 | `requestStart` | not armed | `rejected(notArmed)` | none |
| 27 | `requestStart` | a start guard fails | `rejected(notReady(code))` | none |
| 28 | `requestStart` | ride already active | `rejected(rideActive)`; if the cached start for this id exists → cached reply | none |
| 29 | unknown | — | `rejected(unknownCommand)` | none |

Concurrency rule: the bridge runs on the main actor, so a phone tap and a command are totally ordered;
the table's guards make the second one a no-op or `alreadyInState`. No time-of-arrival tie-breaking.

### `StatusTransportPolicy` (pure)

| Link state | Watch display | Trigger | Live | Context |
| ---------- | ------------- | ------- | ---- | ------- |
| `ready` | active | state change | yes | yes |
| `ready` | active | heartbeat 5 s | yes | at most every 30 s |
| `ready` | off | state change | no | yes |
| `ready` | off | heartbeat 30 s | no | yes |
| `ready` | any | watch asks for a refresh (wrist raise) | yes, immediately | — |
| `ready` | any | crash phase change | yes | yes (exempt from the 5 s cap) |
| not `ready` | any | state change | no | yes |

The watch reports `displayActive` in `WireWatchState` (scene phase / luminance); the phone never assumes it.

### `StartArming` (pure state machine; see also "Start from the wrist")

States: `disarmed`, `armed(until)`, `starting(commandId)`, `consumed`.

| # | From | Event | Guard | To | Effects |
| - | ---- | ----- | ----- | -- | ------- |
| 1 | disarmed | rider taps "Ready to ride" | preconditions pass | armed(now+5 min) | idle timer off; optional dim after delay; publish `armed` |
| 2 | disarmed | rider taps "Ready" | a precondition fails | disarmed | show the failing rows |
| 3 | armed | rider taps Cancel | — | disarmed | publish `ready` |
| 4 | armed | expiry | — | disarmed | publish; notice on phone |
| 5 | armed | app resigns active | — | disarmed | publish; notice |
| 6 | armed | crash event becomes active, or location authorization lost | — | disarmed | publish |
| 7 | armed | `requestStart` accepted | — | starting(commandId) | run the start path |
| 8 | starting | ride becomes active | — | consumed | publish ride status |
| 9 | starting | start fails | — | disarmed | typed reason to the watch |
| 10 | armed | rider taps Start on the phone | — | consumed | normal start |
| 11 | consumed | ride ended / reset | — | disarmed | — |
| 12 | any | undefined | — | same | no-op |

Preconditions: app active; `RideState == idle`; location authorized; if the camera feature is on, framing
was completed this session and no readiness **block** row fails (rear-camera `ReadinessEvaluator`); no
crash event active; watch link `ready`.

### Fan-out, routing, and escalation

`FanOutAlertManager` (rear-camera) calls `AlertRoutingPolicy` with the **channel states** and gets a plan:
an ordered list of sink steps with timeouts. This spec adds the watch channel and the escalation.

| Alert | Watch `ready` | Watch `degraded` / `foregroundOnly` | Watch `unavailable` / `unreachable` | Phone locked |
| ----- | ------------- | ----------------------------------- | ----------------------------------- | ------------ |
| `cautionRearVehicle` (L1/L2) | watch; escalate to audio if no receipt in 1.5 s | watch **and** audio | audio | dropped (stale) |
| crash countdown | watch **and** audio **and** phone UI (all, repeating) | same | audio + UI | notification + audio |
| `cameraInterrupted` | watch; escalate to audio at 1.5 s | watch + audio | audio | notification (primary) |
| `cameraStopped(reason)` | watch; escalate to audio at 1.5 s; notification if the phone is locked | watch + audio | audio | notification |
| `cameraResumed` | watch | watch | audio tick | — |
| `clipSaved` / `clipNotSaved` | watch (no escalation) | watch | audio tick | — |
| `phoneBatteryLow` | watch; escalate to audio at 1.5 s | watch + audio | audio (spoken once) | notification |
| `watchDisconnected` / `watchReconnected` | audio only | audio | audio | — |

Audio does not play together with a **confirmed** watch haptic for `cautionRearVehicle` unless "Also play
a sound" is on (O-W7). The outcome tracker (pure) per alert id: `pending` → `confirmed` (receipt
`played`) | `escalated` (timeout or failure) | `expired`; it also guarantees an alert escalates at most
once and never after its TTL.

Cooldowns (L0–L3):

```
 detector ─▶ RearAlertGate (L0: recording ∧ speed > 2 m/s; demo-forced alerts bypass ONLY this) ─▶ AlertManager.fire
        ─▶ FanOutAlertManager ─▶ AlertRoutingPolicy (L2: caution ≤ 1/3 s; camera notices ≤ 1/min/reason)
              ├─▶ PhoneAudioAlertSink ─ HapticAudioAlertManager / AlertCooldown (L1: 2 s)
              ├─▶ WatchAlertSink ─live─▶ [watch] AlertFreshness ─▶ WristHapticLimiter (L3) ─▶ HapticPatternSelector ─▶ HapticPlaying
              └─▶ LocalNotificationAlertSink / (future ExternalHapticSink)
```

### Readiness screen (`WatchReadinessEvaluator`, pure)

| Row | Pass | Warn | Info |
| --- | ---- | ---- | ---- |
| Watch paired | paired | — | not paired: instructions |
| Whoosh watch app installed | installed | — | not installed: instructions |
| Link | `ready` | `incompatible` ("Update Whoosh on your watch/phone"), `installedUnreachable` ("Open Whoosh on your watch") | — |
| Health permission (watch) | granted | not determined (will ask on the watch) | denied: haptics only while the app is on screen |
| Keep-alive | session can start | other workout running | — |
| Watch battery | ≥ 40% | 15–40% | < 15%: warn strongly |
| Haptics test | last test felt | no test yet / "didn't feel" | — |
| Reminders | | | Silent Mode, Theater Mode, Do Not Disturb, Water Lock, watch haptic strength (Watch Settings → Sounds & Haptics) |
| Audio fallback | shown always | | "If the watch can't be reached, alerts use this phone's sound" |
| Start from watch | `armed` available | | "Ready to ride" action |

Block does not exist in this evaluator: nothing here prevents a ride.

---

## Watch-side design

### Structure

`WatchSessionModel` (`@Observable`, main actor) owns: the `WireLink`, the codec, `WatchRideReducer`,
`WatchCommandTracker`, `CrashCountdownModel`, `WorkoutSessionController` (protocol), `HapticPlaying`
(protocol), `WatchNoticeLog`. SwiftUI views read it and send intents. All logic that can be pure lives in
the package so it is tested with `swift test`; the watch target is a thin shell around system APIs.

### Pages (vertical paging; one primary page)

| Page | Content | Notes |
| ---- | ------- | ----- |
| **Ride** (primary) | Elapsed time (large, tabular, fixed scale); distance (mi) and speed (mph) in a row; chips (icon + text): ride state, camera state, phone link when stale; a crash/countdown takeover appears above everything | at most three numbers |
| **Controls** | Pause / Resume (≥ 60 pt, tap); Save clip (≥ 60 pt, tap, disabled with a reason when the camera is off); Stop (hold ~1.0 s with a progress ring; release cancels; VoiceOver action "Stop ride"). A scrollable page so Stop is deliberate | Crown scroll |
| **Notices** | Last 10 alerts for this ride; unread badge; acknowledge | memory only |
| **Idle / Ready** (no ride) | Readiness line; Start (hold 0.8 s) when `armed`, otherwise "Tap Ready on your iPhone"; haptic preview; last ride summary | |
| **Summary** | Time, distance, average speed, cue count; Save to Health / Discard (default per setting after 60 s) | |
| **Settings** (small) | Default save to Health; "Also play a sound" mirror; complication opt-in (Stretch); diagnostics (counts) | |

Reduced-luminance presentation shows elapsed time and state glyphs only. Brand tokens: Ink background,
Lime primary action, Amber warning (signal lost, camera trouble), Alert red (countdown only), Mist text.
Layout is checked on 40 mm and 44 mm (Cancel ≥ 80 pt must fit **(verify)**).

### `WatchRideReducer` (pure)

Phases: `noLink`, `idle`, `active(fresh|stale)`, `ending`, `summary`. It applies statuses (ignoring `seq`
≤ last for the epoch; resetting on a new `epoch`), local intents, `StatusFreshness` (stale after 15 s
without a message while the display is active), and the link state, and emits a **view model** (numbers,
chips, enabled controls with reasons) and **effects** (send a command, play a pattern, report
`WatchState`). Rows are listed in the test table (WR-1…).

### `ElapsedTimeProjector` and `CrashCountdownModel` (pure)

- Elapsed = `activeMs` at send + (watch monotonic now − watch monotonic at receipt), while `recording` /
  `signalLost`; frozen when `paused`. No phone/watch wall-clock subtraction (L3).
- Countdown remaining = `remainingMs` at send − (watch monotonic now − receipt); the model produces the
  displayed seconds, the VoiceOver announcement schedule (start, every 10 s, last 5 s), and the haptic
  repeat schedule (every 3 s, then every 1.5 s in the last 10 s, at most 20 repeats), and moves through
  `hidden → countdown → cancelling(commandId) → cancelled | tooLate | sending | sent | queued | failed`
  based on replies and status.

### `WatchCommandTracker` (pure)

Tracks each command: `idle → pending(attempt, deadline) → confirmed(reply) | notConfirmed`. Events: tap
(subject to the 500 ms spacing and "already pending"), reply, retry timer (attempts at 0, 2.5, 5 s with
the **same id**), TTL expiry (→ `notConfirmed`, then reconcile from the next status; never auto re-issue),
link loss (→ immediate failure and disabled controls within 1 s), and the crash exception (retry every 1 s
until the deadline; additionally a queue copy).

### Keep-alive: `WorkoutSessionStateMachine` (pure) and `HKWorkoutSessionController`

States: `off`, `authorizing`, `preparing`, `running`, `paused`, `stopping`, `ended(saved|discarded)`,
`failed(reason)`, `unavailable(reason)`.

| # | From | Event | Guard | To | Effects |
| - | ---- | ----- | ----- | -- | ------- |
| 1 | off | ride becomes active, or phone launched the app for a workout, or app opened mid-ride | authorization unknown | authorizing | request share-only authorization (explain first) |
| 2 | off | same triggers | authorized | preparing | create session + builder (cycling; location type per O-W4); start |
| 3 | authorizing | granted | — | preparing | as row 2 |
| 4 | authorizing | denied | — | unavailable(healthDenied) | report `WatchState`; foreground-only |
| 5 | preparing | session running | — | running | report; `hapticsArmed = true` |
| 6 | preparing | error or 10 s timeout | — | failed(startFailed) | report; retry per row 13 |
| 7 | running | ride `paused` | — | paused | `pause()` **(verify T11: if the app is not kept alive, keep running and add a pause event instead)** |
| 8 | paused | ride `recording` | — | running | `resume()` |
| 9 | running, paused | ride `finished` / `idle` | — | stopping | stop activity; show summary; start the 60 s default-choice timer |
| 10 | stopping | Save (or timeout with default Save) | — | ended(saved) | end collection; save; end session |
| 11 | stopping | Discard (or timeout with default Discard) | — | ended(discarded) | discard; end session |
| 12 | running, paused | `errorAnotherWorkoutSessionStarted` | — | failed(anotherWorkout) | report; notice; do not fight the other workout |
| 13 | failed(startFailed or systemEnded) | retry timer | ride active ∧ tries < 2 | preparing | retry after 15 s |
| 14 | running, paused | session ended by the system | ride active | failed(systemEnded) | report; row 13 |
| 15 | running, paused | no phone contact for the orphan timeout (15 min) | — | stopping | notice "Ride session ended: iPhone not responding"; default choice rules |
| 16 | running, paused | watch battery ≤ 5% | — | stopping | end early; notice |
| 17 | off | relaunch finds a recoverable session | — | preparing | `recoverActiveWorkoutSession`; re-attach delegates; resync |
| 18 | ended | next ride, or summary dismissed | — | off | reset |
| 19 | any | undefined | — | same | no-op |

`HKWorkoutSessionController` requests authorization **only to share the workout type**, reads none, keeps
CPU minimal (no per-second work; clock ticked from an anchor), and contains the only HealthKit code on the
watch.

### Haptic playing

`HapticPlaying` (protocol): `play(cue)`, `isActive`. `WKHapticPlayer` calls `WKInterfaceDevice.play` only
when the app state is `active` (a workout session counts), reports `suppressedNotActive` otherwise, and runs
patterns in one serial task with cancellation so a higher tier can preempt. Steps respect the platform's
100 ms minimum.

---

## Haptic catalog

Cues are `WKHapticType` values by name. Sequences are **starting hypotheses**: the final choice is made on
the wrist in task 19 (spike test T1: distinguish them wrist down, over a sleeve, and on a rough road).
Gaps are the delay after the cue. Every pattern is data in `HapticPatternSelector`.

| Event | Tier | Pattern (cue, gap ms → …) | Repeat / reminder | Text (short, honest) |
| ----- | ---- | ------------------------- | ----------------- | -------------------- |
| Crash countdown start | critical | notification 400 → failure 400 → failure | every 3 s; every 1.5 s in the last 10 s; stops at end/cancel; ≤ 20 | "Crash detected" (DEMO labeled for drills) |
| Crash cancelled (confirmed by reply) | confirm | success | — | "Cancelled" |
| Cancel failed / too late | caution | failure 400 → failure | — | "Too late — alert is sending" |
| Countdown ended, alert sending | notice | stop 300 → stop | — | "Sending alert" |
| Rear-vehicle cue, level 1 (experimental) | caution | directionUp 300 → directionUp | storm backoff 3→6→12 s | "Vehicle cue (experimental)" |
| Rear-vehicle cue, level 2 | caution | directionUp 250 → directionUp 250 → directionUp 400 → notification | same cooldown | "Vehicle cue — repeated (experimental)" |
| Camera interrupted | notice | retry 400 → retry | once more at +60 s if unresolved | "Camera paused" |
| Camera resumed | confirm | start | — | "Camera recording" |
| Camera stopped (policy / failed) | caution | failure 500 → failure 500 → failure | reminder at +60 s, ≤ 2 | "Camera stopped: <reason>" |
| Clip saved | confirm | success | — | "Clip saved" |
| Clip not saved | notice | failure | — | "Clip not saved" |
| Phone battery low (≤ 20%) | notice | directionDown | — | "Phone battery 20%" |
| Phone battery critical (≤ 8%) | caution | directionDown 350 → directionDown | — | "Phone battery low — camera may stop" |
| Link lost (watch-originated, after 20 s) | notice | retry 600 → directionDown | — | "iPhone not responding" |
| Link restored | confirm | click | — | "iPhone connected" |
| Ride started / stopped | confirm | start / stop | — | |
| Ride paused / resumed | confirm | click | — | |
| Command not confirmed | notice | failure | — | "Not confirmed" |

**Selection rules** (`HapticPatternSelector`, pure): rear-vehicle level 2 is chosen when the context
confidence is high (≥ 8 of 10) **or** a second cue is admitted within 10 s of the previous; otherwise level
1. Position hints (left/center/right) change the text only. Directional navigation cues
(`navigationLeftTurn` / `navigationRightTurn`) are **not** used for hints: they mean "turn" and would
conflict with navigation meaning (considered, rejected; Future). Cue meanings: `retry` (temporary
failure) for interruptions, `failure` for stops, `directionDown` (value dropped) for battery,
`directionUp` (value rose / threshold crossed) for the rear cue, `start` for recovery; where the match is
loose the limit is recorded here and tuned in task 19 (O-W6).

**Distinctness test** (HP-1): every pair of entries with different meanings has a different signature
(cue types, count, or gap profile); the three important ones differ in first cue or count.

### `WristHapticLimiter` and `AlertFreshness` (pure; table-driven)

| Rule | Behavior |
| ---- | -------- |
| Freshness | `age = receiveSkewAdjusted(createdAgoMs, link latency)`; if `age > ttl` → `suppressedStale` |
| Duplicate id | `suppressedDuplicate` |
| Not active | player reports `suppressedNotActive` |
| Tier preemption | a higher tier cancels the pattern in progress; a lower tier arriving during a higher one is dropped (`suppressedHigherTier`) |
| Minimum gap | at least 1.0 s between pattern starts (except preemption by `critical`) |
| Per-kind cooldown | rear cue 3 s base; camera notices 60 s per reason; mirrors L2 |
| Storm backoff | rear cue cooldown 3 → 6 → 12 s while cues keep arriving within 30 s; resets after 30 s quiet |
| Demo | a demo-flagged alert is played only when the latest status says `demo == true` |
| Disabled | after the user turns the watch off: everything is dropped with `suppressedDisabled` |
| Reporting | every decision returns a `WireAlertReceipt` result; counts feed the summary |

---

## Start from the wrist

```
 phone: Mount & frame done ─▶ rider taps "Ready to ride — start from watch" ─▶ StartArming.armed (5 min)
        (idle timer off; may dim; status.start = armed)
 watch: Idle page shows "Hold to start" (enabled only when status.start == armed)
        rider holds 0.8 s ─▶ command requestStart(commandId, holdConfirmed)
 phone: RemoteCommandReducer row 25 ─▶ StartArming.starting ─▶ same action as the Start button (startedFromWatch)
        mount grace skipped (or 3 s) ─▶ camera starts ─▶ ride mode ─▶ reply(accepted, rideId)
 watch: sees status.state == recording ─▶ starts the keep-alive session ─▶ reports WatchState(running)
        if the session fails ─▶ announced on the phone's audio; the ride is unaffected
```

Rejections render short instructions: `notArmed` → "Tap Ready on your iPhone"; `notReady(camera)` →
"Frame the camera on your iPhone"; `notReady(location)` → "Allow location on your iPhone"; link failure →
"iPhone not responding".

If the owner leaves O-W5 unapproved, the Idle page shows the readiness line only and the ride starts on the
phone; nothing else in this spec depends on the start command.

---

## What the watch can and cannot do when the phone app is not running

**Normative matrix.** "App state" is the iPhone's Whoosh state. A ✗ means the control is **not offered as
usable** (it is shown disabled with the reason), never shown as working.

| # | iPhone app state | Link | Start | Pause / Resume / Stop / Save clip | Receive rear cue / camera notices | Cancel crash countdown | What the watch shows | Notes |
| - | ---------------- | ---- | ----- | --------------------------------- | -------------------------------- | ---------------------- | -------------------- | ----- |
| 1 | Whoosh not installed on the phone / watch not paired | — | ✗ | ✗ | ✗ | ✗ | the watch app cannot exist | readiness explains |
| 2 | **Not running** (force-quit or terminated), no ride | unreachable or unresponsive | ✗ | ✗ | ✗ (nothing is detecting) | ✗ | "Open Whoosh on your iPhone"; last ride summary; local pattern preview | a watch `sendMessage` may wake a system-terminated app but a force-quit app is not relaunched **(verify T9)**; not relied on |
| 3 | Running in the background / suspended, no ride | maybe reachable | ✗ | ✗ | ✗ | ✗ | same as row 2 | a ride cannot start from the background (camera, When-In-Use start) |
| 4 | **Foreground, no ride, not armed** | ready | ✗ ("Tap Ready on your iPhone") | n/a | n/a | n/a | readiness, haptic test, summary | |
| 5 | **Foreground, armed** | ready | ✓ hold 0.8 s | n/a | n/a | n/a | "Hold to start" | |
| 6 | **Ride active** (foreground ride mode, or locked with the `location` background mode) | ready | n/a | ✓ | ✓ (watch first, audio on timeout) | ✓ | full Ride/Controls pages | the phone process is alive because the ride is active |
| 7 | **Ride active, then the app is terminated** (crash, jetsam, force-quit) | goes stale | ✗ | ✗ (fail visibly) | ✗ (nothing is detecting or recording) | ✗ | after 60 s: "iPhone app may have closed. Open Whoosh on your iPhone to recover your ride." Session continues until the rider ends it or 15 min | the MVP interrupted-ride recovery runs when the phone app is reopened |
| 8 | Ride active, iPhone and watch out of range / Bluetooth off / Airplane mode | unreachable | ✗ | ✗ (fail visibly) | ✗ → the **phone** says "Watch disconnected" through audio after 20 s | ✗ | stale status; "iPhone not responding" | recording continues on the phone |

**Reconnect sequence** (Requirement 10.7):

1. `reachability(true)` → both sides send `hello`; on overlap → `ready`.
2. The phone sends a full `status`, the active crash countdown (if any) with its remaining time, and
   `replay` records of unread must-arrive notices (log only, no buzz unless within their TTL).
3. The watch sends `WatchState`; it clears the stale presentation; it plays the "iPhone connected" confirm
   cue once.
4. Commands that were `notConfirmed` stay resolved from status (the watch never re-issues them).
5. A new `epoch` (new ride) discards watch state tied to the previous ride.
6. If the watch app had been killed and the phone sees `installedUnreachable` during a ride, the phone
   retries `startWatchApp` (3 times, 15 s apart) and reports the result in the channel state.

---

## Complications and Smart Stack (Stretch)

A WidgetKit complication shows a system-rendered timer (anchor-driven, so no per-second updates) and the
ride-state glyph, with a deep link to the app. It is **opt-in, off by default**, and shows only time and
state. The phone does not push per-update complication data (50 per day); the watch app, alive during the
ride, writes a small shared record and reloads the timeline on state changes. Live Activities mirrored to
the Smart Stack exist only on newer watchOS and are out of scope (**verify** absent on watchOS 10).

---

## Accessibility

- Labels and traits on every control; icon + text for all state; no color-only meaning.
- Stop has a VoiceOver custom action (matching `HoldToStopButton`); hold has a generous drift tolerance
  (verify the value on wet fingers); Crown-confirm is a Stretch alternative.
- Cancel is full width and ≥ 80 pt tall; pause/resume and save-clip ≥ 60 pt; the three Ride numbers use a
  fixed scale (like the phone's ride metrics) while surrounding text scales with Dynamic Type.
- VoiceOver announcements for state changes; the countdown at start, every 10 s, and the final 5 s.
- Reduce Motion: static countdown, no pulse. No flashing.
- Haptics are never the only signal.

---

## Privacy and network invariants

| Data | Where | Rules |
| ---- | ----- | ----- |
| Ride status sent to the watch | transient over WatchConnectivity; the latest context is kept by the system | Only the fields in `WireRideStatus` (enums, rounded numbers, counts). **No coordinates, routes, video, thumbnails, clip ids, contact names or numbers, or message text.** |
| Crash countdown on the watch | in memory | Event id, relative remaining time, drill flag, **contact count**, phase. Never names or numbers; never location. |
| Notice log | watch memory, current ride only | Kind, time into ride, reason code. Discarded at the next ride; never persisted. |
| Last ride summary | watch (small local record) | Totals and counts only. No route. |
| Watch settings | watch `UserDefaults` | Default-save-to-Health, "also play a sound", complication opt-in. |
| Workout (optional) | Apple Health on the rider's devices | Write-only workout type; no Whoosh read; never uploaded by Whoosh; the rider chooses Save or Discard. |
| Wire diagnostics | memory / local log | Ids, types, outcomes only. |

- **Network invariant unchanged:** while neither ride sync nor crash alerts is enabled the app makes no
  network requests. The watch app makes **none**, ever; WatchConnectivity is device to device.
- **Allowlist test (PR-1):** serializes every wire type and fails on a field outside the allowlist or any
  string longer than a short code.
- **`scripts/privacy-check.sh` changes (task 2; not made by this job):** (1) scan `WhooshWatch/` and
  `Packages/WhooshWire/Sources` as well as `Whoosh/`; (2) `import WatchConnectivity` only in
  `Whoosh/Services/Remote/WCSessionWireLink.swift` and `WhooshWatch/Services/Link/`; (3) `import HealthKit`
  and `HKWorkoutSession` only in `WhooshWatch/Services/Workout/` and the single phone file that calls
  `startWatchApp`; (4) `WKInterfaceDevice` haptic calls only in `WhooshWatch/Services/Haptics/`;
  (5) the package, `Models`, and `Metrics` import Foundation only; (6) `WhooshWatch/` imports no
  CoreLocation, MapKit, AVFoundation, Photos, networking, or analytics; (7) network-layer folders must not
  reference wire types; (8) keep the existing honest-copy rules, applied to the watch strings.
- **Steering deltas proposed (applied by task 2):**
  - `privacy.md`: a new "Apple Watch companion" section with the table above and the rules in this list; a
    permissions row **HealthKit (watch): share workout type only, when the rider first starts a
    watch-supported ride or taps "Set up watch alerts"; `NSHealthShareUsageDescription` and
    `NSHealthUpdateUsageDescription` on the watch target (confirm whether the share key is required with an
    empty read set)**; a row **Notifications (watch): only when crash alerts are enabled and the watch is
    used**; and the sentence that Silent degradation of recording must be announced on the wrist or audio.
  - `tech.md`: rows for the watchOS app (SwiftUI, watchOS 10+), WatchConnectivity (confined as above),
    HealthKit workout session on the watch, WatchKit haptics, WidgetKit (Stretch), and the local package.
  - `product.md` and `team-plan.md`: cross-references already added by this job.
- **Permission strings (final copy in task 29):** HealthKit share: "Whoosh uses a cycling workout so haptic
  alerts keep working with your wrist down, and can save your ride to Apple Health when you choose."

---

## Latency, battery, and performance budgets

### Hypotheses (*verify*; none is a promise)

| Item | Hypothesis |
| ---- | ---------- |
| Link round trip while reachable | p50 ≤ 0.5 s, p95 ≤ 1.5 s |
| Alert to wrist haptic | p95 ≤ 1.5 s; after 1.5 s without a receipt the fan-out escalates |
| Command to confirmation | p95 ≤ 2 s |
| Crash cancel to confirmation | p95 ≤ 2 s |
| `startWatchApp` to session running | measured; forum reports up to 30–60 s (2017) |
| Watch battery, keep-alive + link | measured over 60 min; no claim before |
| Phone impact of the link | negligible next to camera + GPS; re-measure once |
| Haptic engine | each play costs power; limiter bounds it; HR collection pauses while it runs |

### Measurement protocol (task 28; extends the spike's T1–T8)

Record the watch model, watchOS version, iPhone, iOS version, battery start/end, Focus modes, and repeat
each condition at least 5 times (50 samples for latency percentiles).

| ID | Condition | Measure |
| -- | --------- | ------- |
| M1 | Watch app on screen, phone idle | RTT distribution |
| M2 | Wrist down, workout running, phone screen on in ride mode | RTT; haptic felt x of 10 |
| M3 | Wrist down, workout running, phone locked with background location | RTT; felt x of 10 |
| M4 | Airplane mode toggle, then walk 10 m away and back | time to fail visibly; time to recover |
| M5 | Phone app force-quit, then terminated by system | what the watch can do (matrix rows 2, 3, 7) |
| M6 | 60 min cycling workout, session only (location type per O-W4) | watch battery % per 10 min |
| M7 | M6 + live status every 5 s + one caution cue per 30 s | watch battery % per 10 min |
| M8 | Same as M6 with `.outdoor` for comparison | watch battery % per 10 min |
| M9 | `startWatchApp` from a locked/dim watch, from a charging watch | time to session running |
| M10 | Paused workout session with an alert | felt x of 10 |

### Measured results

*(empty until task 28; no latency, battery, or reliability claim is made before it is filled.)*

---

## Error and degradation handling

| Scenario | Behavior | Req |
| -------- | -------- | --- |
| No watch / not installed / not paired | Phone channels carry everything; readiness explains | 1.3, 3, 20.1 |
| Setting turned off | Traffic stops; commands rejected `watchDisabled` | 1.8 |
| Watch unreachable mid-ride | Controls disabled with reason; stale presentation; phone says "Watch disconnected" after 20 s | 10.4, 10.5 |
| Phone app gone mid-ride | After 60 s: "iPhone app may have closed"; session continues; orphan timeout | 10.6 |
| Incompatible versions | Calm message on both; phone channels | 5.4, 20.3 |
| Keep-alive refused / lost | Reported; fan-out treats the watch as degraded; audio also | 4.12, 20.2 |
| Another workout started | Session ends; reported; audio also; readiness hint | 4.8 |
| Health denied | Foreground-only; reported; audio also | 4.5 |
| Haptics unavailable (Theater Mode, Water Lock, DND unknown) | `suppressed` receipt; phone audio escalates | 11.8, 13.2 |
| Command reply lost | Same-id retries; cached reply; reconcile from status | 6.5 |
| Command stale (old ride) | `ignored(staleRide)` | 6.4 |
| Duplicate alert / command | Deduped | 12.5, 6.2 |
| Delayed alert after a stall | Dropped as stale; no burst | 12.4 |
| Countdown cancel loses the tie | Reply `tooLate`; watch says so | 15.4 |
| Watch battery low / critical | Reported; phone announces once; session ends at 5% | 20.5 |
| Queue backlog | Capped; stale cancelled at ride end | 20.4 |
| Simulator limits | `transferUserInfo` untestable in the simulator; use paired devices | 5.11 |

---

## Testing strategy

All logic is unit-tested with fakes; pure policies and reducers are table-driven. Package tests run with
`swift test` on a Mac; phone-side tests run with `scripts/test.sh`. Manual device checks go in
`manual-qa.md` (task 28).

| ID | Area | Scenario → assertion |
| -- | ---- | -------------------- |
| MC-1…10 | Codec | Round trip every type; deterministic encoding; golden fixtures; unknown field ignored; unknown enum → `unknown`; missing field → typed error; wrong type → typed error; oversized → typed error; never crashes on random bytes |
| CV-1…6 | Versions | Overlap picks the highest; disjoint → `incompatible`; previous version accepted; new minor field ignored by old reader; `hello` capabilities |
| PR-1 | Privacy | Allowlist: no coordinate/name/number/free-text field in any wire type; no string over the short-code limit |
| LS-1…17 | Link state | One test per row of the link table |
| LB-1…8 | Loopback | Delay, drop, duplicate, reorder, unreachable window; commands survive duplicates; alerts do not replay |
| CD-1…6 | Dedupe | Hit returns the cached reply; expiry at 5 min/128; replay after cache eviction is judged by state guards |
| RC-1…29 | Command reducer | One test per row of the reducer table |
| SA-1…12 | Arming | One test per row; expiry with a test clock |
| TP-1…8 | Transport policy | Each cell of the policy table |
| EP-1…6 | Elapsed projector | Advances while recording; frozen when paused; no wall-clock dependence; new epoch resets |
| SF-1…5 | Freshness | Stale threshold; display-off rule; refresh on raise |
| HP-1…6 | Patterns | Catalog completeness; uniqueness of signatures; level-2 selection; 100 ms minimum spacing; no navigation cues |
| HL-1…10 | Limiter | Min gap; preemption by tier; per-kind cooldown; storm backoff and reset; duplicate; demo gating; disabled |
| AF-1…5 | Alert freshness | TTL per kind; skew tolerance; replay records never buzz |
| WR-1…n | Watch ride reducer | Seq/epoch handling; stale transitions; control enablement; crash takeover show/hide |
| CT-1…8 | Countdown model | Remaining from relative time; announcements; haptic repeat schedule; cancelling → cancelled/tooLate/sending; drill label; failure retry each 1 s |
| WS-1…19 | Workout session machine | One test per row of the session table |
| WC-1…6 | Command tracker | Spacing, pending, retries with the same id, TTL expiry, link loss, crash exception |
| FO-1…10 | Fan-out / escalation | Plan per cell of the routing table; escalation at most once; never after TTL; audio not concurrent with a confirmed watch cue unless enabled |
| WE-1…6 | Channel evaluator | Link + `WatchState` → channel state table |
| RR-1…8 | Readiness evaluator | Each row pass/warn/info |
| MAP-1…6 | Wire mapper | Domain → wire mapping drops everything not in the allowlist; rounding; banner/camera code mapping |
| INT-1…6 | Integration (loopback) | Phone remote + watch model: pause/resume/stop/save clip/cancel crash end to end with fakes; stale ride id; duplicate command; reply lost |
| UI | Views | Previews with fakes; accessibility labels asserted where practical |

**Demo-mode coordination for testing:** the demo-mode spec's forced rear-vehicle alert and crash drill
exercise the wrist without riding (they pass through the same fan-out, labeled DEMO). The readiness screen's
haptics test and the pattern preview work without demo mode so the watch can always be checked before a ride.

Manual (device, not automatable): spike T1–T14; wrist-down haptics; `startWatchApp` launch; force-quit
behavior; paused session; Silent/Theater/DND/Water Lock; notification action while a workout runs; battery
and latency protocol M1–M10; 40 mm vs 44 mm layout; gloved/wet Stop; VoiceOver on the watch.

---

## Seam amendments to approved specs

This spec amends approved documents only here. The approved documents are **not edited by this authoring
job**; the named task applies each edit after owner approval.

| # | Approved spec / item | Amendment | Applied by |
| - | -------------------- | --------- | ---------- |
| A1 | rear-camera Req 13.2 "Start is not a remote command in v1" | `requestStart` is allowed, armed-gated (Requirement 9) | task 23 |
| A2 | rear-camera `RideRemoteCommand` | add `requestStart`; add envelope-level `commandId`, `rideId`, `holdConfirmed`, `crashEventId` | task 13 |
| A3 | rear-camera `RideStatus` | additive: `rideId`, `epoch`, `seq`, `start` readiness, `demo`, crash phase and contact count, clip count | task 13 |
| A4 | rear-camera `AlertSink` / `AlertContext` | add alert id, tier, TTL, demo flag, confidence, hint; add an outcome callback | tasks 13, 14 |
| A5 | rear-camera `AlertKind` | add `watchDisconnected`, `watchReconnected` | task 9 |
| A6 | rear-camera `ScreenModeStateMachine` | rows for `armed` (idle timer off, optional dim) and `startedFromWatch` (skip or shorten the grace) | task 23 |
| A7 | rear-camera privacy rule 3 | WatchConnectivity allowed in `WCSessionWireLink` (phone and watch) | task 2 |
| A8 | crash-response coordinator | a read-only countdown snapshot (event id, remaining ms, drill flag, contact count, phase) and a rider-cancel that reports `cancelled` / `tooLate` / `notCancellable` | task 21 |
| A9 | crash-response consent copy | add: the watch cannot guarantee that it is seen or that a cancel arrives | task 21 |
| A10 | `privacy.md`, `tech.md`, `scripts/privacy-check.sh`, `project.yml` | per "Privacy" above and task 3 | tasks 2, 3 |
| A11 | demo-mode spec | none beyond honoring `AlertContext.isDemo`; confirm at owner review | task 26 |

---

## Decisions

| # | Decision | Choice | Why | Status |
| - | -------- | ------ | --- | ------ |
| D-W1 | Channel | WatchConnectivity (live / context / queue); mirrored workout channel as a documented fallback | Matches the seam, the spike, and Apple's mechanisms | **OPEN O-W10** |
| D-W2 | Keep-alive | Cycling `HKWorkoutSession` on the watch; no extended runtime session | Only documented way to run and play haptics with the wrist down; extended sessions don't cover cycling | **OPEN O-W2** (spike-gated) |
| D-W3 | Target | watchOS 10.0 | Pairs with iOS 17; runs on every SE generation | **OPEN O-W1** |
| D-W4 | Shared code | Local Foundation-only package `Packages/WhooshWire` | One contract, fast tests, cannot import UI | Proposed |
| D-W5 | Authority | The phone decides everything; the watch is remote + display + actuator | Reuses the existing state machines | Proposed |
| D-W6 | Command delivery | Never queued; visible failure; one guarded exception (crash cancel) | A stale control is worse than a failed one | Proposed |
| D-W7 | Command shape | State-based, `commandId` + `rideId`, replies embed status | Idempotent, reconcilable, no toggle ambiguity | Proposed |
| D-W8 | Wire payload | Envelope + JSON `Data`; enums/numbers/ids only; no free text | Privacy, golden tests, evolvability | Proposed |
| D-W9 | Time | Duration-at-send + local monotonic clock; relative deadlines | Immune to phone/watch clock skew | Proposed |
| D-W10 | Status transport | Display-aware: live while the display is on, context otherwise | Battery | Proposed |
| D-W11 | Haptics | Patterns as data with tiers, unique signatures, preemption | Testable, distinct, tunable | **OPEN O-W6** (final on the wrist) |
| D-W12 | Limits | Layers L0–L3, additive; storm backoff; freshness; dedupe | Never spam, never hide | Proposed |
| D-W13 | Escalation | Watch first; audio at 1.5 s without a receipt; notification as backup | Reliability without double-buzzing | **OPEN O-W7** (concurrent audio default) |
| D-W14 | Start | Armed, rider-initiated, foreground only | iOS limits; accident safety | **OPEN O-W5** |
| D-W15 | Crash on the wrist | Count only; relative deadline; true outcome; queue-copy cancel; backup notification | Reachable cancel without exposing contacts | **OPEN O-W8** |
| D-W16 | Health | Write-only workout type; Save/Discard; location type per decision | Apple's guidance; minimal data | **OPEN O-W3, O-W4** |
| D-W17 | Watch storage | No ride data persisted; in-memory notice log; small summary record | Privacy | Proposed |
| D-W18 | Complication | Stretch; opt-in; timer + state only | Face visibility | **OPEN O-W9** |
| D-W19 | Folder map | `WhooshWatch/`, `Packages/WhooshWire/`, `Services/Remote`, `Features/Watch` | Narrow privacy rules | Proposed |
| D-W20 | Confirmation levels | Stop hold 1.0 s; start hold 0.8 s; others tap; cancel single tap ≥ 80 pt | Parity with the phone; rain tolerance | **OPEN O-W11** |
| D-W21 | Spike first | No production watch code before a go decision | The central bet is unmeasured | Proposed |

### Owner resolution (October 24, 2026)

The iOS owner approved this spec and accepted every recommendation below (O-W1–O-W11) as written;
this note is binding. O-W1: the owner's watch is an Apple Watch SE (2nd generation), which runs
current watchOS; the app still targets watchOS 10.0 so older team watches work.

### Open decisions for the owner (now resolved; recommendations accepted)

| # | Question | Recommendation | Affects |
| - | -------- | -------------- | ------- |
| **O-W1** | Which Apple Watch SE do you own, and what watchOS deployment target? | Check the model (Apple Support "identify your Apple Watch model"). Set the target to **watchOS 10.0**: pairs with iOS 17 and runs on SE 1, 2, and 3. Raise it only if you want a newer API. | Requirement 2; tasks 0, 3 |
| **O-W2** | Keep the watch app alive with a cycling `HKWorkoutSession`? | **Yes, gated on the spike.** No other documented mechanism fits cycling. If the spike fails, use the fallback ladder (F1 mirrored channel, F2 foreground-only). | Requirement 4; tasks 1, 18 |
| **O-W3** | Save the ride to Apple Health? | **Offer Save / Discard on the watch with a persisted default of Save** (write workout type only, read nothing, nothing uploaded by Whoosh). Always-discard is possible but a keep-alive-only use of a workout session is a possible App Review question. | Requirement 16; tasks 18, 20, 29 |
| **O-W4** | Workout `locationType`? | **`.unknown`** first (Whoosh does not use watch GPS; the phone records the route), verified to avoid GPS drain and to keep background reliability; fall back to `.outdoor` only if `.unknown` fails the spike. Never `.indoor` (it would mislabel the ride). No location permission on the watch either way. | Requirement 4.10; tasks 1, 18 |
| **O-W5** | Allow start from the wrist (amends rear-camera 13.2)? | **Yes, armed-gated**, shipped after pause/resume/stop (Tier 2). The phone owner arms; expiry 5 minutes. | Requirement 9; tasks 7, 23 |
| **O-W6** | Haptic mapping | Adopt the catalog as a starting point; **finalize on the wrist** (task 19) after spike test T1. Never use navigation cues for position hints. | Requirement 11; tasks 8, 19 |
| **O-W7** | Should audio also play when a watch haptic is confirmed? | **No by default**; escalate to audio only when the watch does not confirm in 1.5 s; offer "Also play a sound" (off) and always use all channels for the crash countdown. | Requirement 13.3; tasks 9, 14 |
| **O-W8** | Crash countdown on the wrist: contact names, a backup notification, Send now / 911? | **Count only** (no names or numbers); **yes to a watch-local time-sensitive notification with an "I'm OK — Cancel" action** as a backup (verify it works while a workout runs); **no** Send now or Call 911 on the watch. | Requirement 15; task 21 |
| **O-W9** | Complication / Smart Stack scope | **Stretch, opt-in, off by default**, timer and state only. | Requirement 17; task 30 |
| **O-W10** | Primary channel | **WatchConnectivity**, with the mirrored-workout channel evaluated in the spike and held as fallback F1. | Requirement 5.1; tasks 1, 31 |
| **O-W11** | Confirmation levels | Stop hold 1.0 s; start hold 0.8 s; pause/resume/save-clip tap; cancel tap ≥ 80 pt; Crown confirm as a Stretch alternative. Accept that rain can cause an accidental pause (visible, instantly reversible) and that Water Lock disables touch. | Requirement 6.7; tasks 11, 20 |

### Owner resolution

*(pending — to be recorded here after review. This spec is not binding until the owner resolves
O-W1 … O-W11.)*

---

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| **The workout-session bet fails on the owner's watch** (haptics or reachability not reliable with the wrist down) | The headline feature is unavailable | Spike first (task 1); fallback ladder F1–F3; audio always available |
| **Watch battery drain** over a long ride | Watch dies before the ride ends (SE, especially 1st generation) | Measure M6–M8; `.unknown` location type; display-aware status; limiter; show watch battery before the ride; end the session at 5% |
| **Haptics not felt** (sleeve, glove, vibration, strength setting, mode) | Missed cue | Distinct patterns; on-wrist tuning; haptics test; reminders; audio escalation; honest "cannot guarantee" copy |
| **Silent mode / Theater / DND / Water Lock** unknown effect on `play(_:)` | Silent failure | Verify T14; receipts report `suppressed`; readiness reminders; escalation |
| **Accidental pause/stop in rain** | Lost data or a stopped ride | Stop needs a hold; pause is instantly reversible and visible; start needs a hold; Water Lock reminder |
| **Command or alert arrives late** | Wrong action / wrong cue | Ride id guard, TTL, freshness, dedupe, no queueing |
| **Wrong cancel semantics** | Rider thinks a crash alert was cancelled when it was sent | Reply-confirmed outcomes only; `tooLate` shown honestly; the phone keeps its own cancel and audible countdown |
| **Contact data exposure on a wrist** | Privacy | Count only; allowlist test |
| **App Review** (workout session as keep-alive; HealthKit justification) | Rejection | Clear in-app indication; Save/Discard; write-only workout type; honest purpose strings; review notes (task 29) |
| **`startWatchApp` unreliable or slow** | The watch isn't ready at ride start | Retry with backoff; readiness screen; the watch can also be opened by the rider; audio fallback |
| **Another workout starts on the watch** | Session ends mid-ride | Detect, report, audio; readiness hint |
| **Swift 6 concurrency with WatchConnectivity/HealthKit delegates** | Build friction, data races | Explicit actor boundaries in adapters; the spike used Swift 5 mode (L7) |
| **Package/project complexity** | Setup time | Local package is small; fallback is a synced shared folder |
| **Wire drift between phone and watch builds** | Features silently fail | Version negotiation, golden fixtures, N−1 support, readiness warns |
| **Overclaiming** | Trust | Honest copy rules; "experimental"; "cannot guarantee detection or delivery"; privacy script on watch strings |
| **Scope creep** (complications, BLE device, Garmin/Whoop) | Time | Stretch/Future tags; Garmin and Whoop explicitly out of scope |
