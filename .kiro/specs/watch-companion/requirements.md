# Requirements — Whoosh Apple Watch Companion

**Status: DRAFT — awaiting owner approval (October 24, 2026).** No code may be written until the
iOS owner approves `requirements.md`, `design.md`, and `tasks.md`, and the feasibility spike
(`tasks.md` task 1) has produced a go decision. This spec contains **no Swift code** by design.
Open decisions are **O-W1 … O-W11** (`design.md`, "Decisions"), each with a recommendation.

## Introduction

Whoosh is an iOS cycling-safety app. The approved **rear-camera** spec (`../rear-camera/`) mounts
the phone on the back of the seat, facing traffic. From that moment the phone screen is out of the
rider's sight and reach, so **the wrist is the only surface the rider can see and touch during a
ride**. That spec chose an Apple Watch companion as the in-ride surface (its open decision O-CAM1,
approved) and defined the seams the watch needs (`RideStatus`, `RideRemoteControl` /
`RideRemoteCommand`, and the `AlertSink` fan-out) but deliberately left the watch itself, and the
feasibility questions around it, to this spec. The approved **crash-response** spec
(`../crash-response/`) adds a second reason: its countdown needs a cancel the rider can reach
without touching the phone (its design "Risks" table).

This spec adds the **Whoosh watchOS app** and everything on the phone that talks to it:

- **Controls:** start (armed, from the wrist), pause, resume, press-and-hold stop, and "Save clip".
- **Live status:** ride time, distance, speed, and ride/camera/phone-link state.
- **Wrist haptics:** distinct patterns by urgency for the experimental rear-vehicle cue, camera
  trouble, clip/battery notices, and the crash countdown.
- **Crash countdown on the wrist:** a large Cancel, the not-a-guarantee wording, drills labeled DEMO.
- **A pre-ride readiness screen on the phone:** "watch connected, haptics test".

The owner has an **Apple Watch SE** (generation to be confirmed, open decision O-W1). The owner also
has a **Garmin fenix 6x and a Whoop; both are out of scope** and nothing here builds for them
(Requirement 23). Role C's vibration proposal (`../../team/vibration-alert-proposal.md`) found no
documented way for an app to trigger a Whoop; this spec does not revisit that.

### What is known, what is not (read this first)

- Role C's throwaway prototype (`../../../spikes/watch-haptics/`) was written to answer the
  feasibility questions, but **it has never been compiled or run on a device and its results table
  is empty**. This spec treats its research table as hypotheses and cites it for learnings only
  (design, "Spike learnings").
- On October 24, 2026 the Apple reference pages marked **Checked** in `design.md` were fetched from
  `developer.apple.com` and `support.apple.com`. They confirm the mechanisms this spec depends on
  (a workout session keeps a watch app running and allowed to play haptics; `sendMessage` reaches
  the watch only while it is running; `startWatchApp` can launch the watch app for a workout).
  They do **not** prove behavior on the owner's watch. Everything tagged **(verify)** is a
  hypothesis for the spike (task 1) or a device check.
- The design therefore has a **go / no-go gate** (task 1) and a documented **fallback ladder**
  (`design.md`, "Fallback ladder") so the phone-only audio path remains the safety net.

Related specs and documents (reference, do not duplicate):

- `../ride-recording-mvp/` — implemented ride engine: `RideSessionViewModel` intents, `RideState`,
  hold-to-stop, `AlertManager`.
- `../rear-camera/` — approved; defines `RideStatus`, `RideRemoteControl`, `AlertSink`,
  `FanOutAlertManager`, `AlertRoutingPolicy`, camera states, ride mode. **This spec amends it in a
  few recorded places** (Requirement 1.9; `design.md` "Seam amendments").
- `../crash-response/` — approved; countdown, `riderCancel`, drill template.
- The **demo-mode spec** (a parallel spec on another branch: single Demo mode toggle, simulated
  rides, forced rear-vehicle alerts, crash drill) — referenced **by name only**; this spec neither
  creates nor edits its files (Requirement 21.5).
- `../../steering/privacy.md`, `product.md`, `tech.md`, and `../../team/team-plan.md`.

## How to read this document

- Acceptance criteria use EARS-style phrasing (WHEN/WHILE/IF ... THEN ... SHALL ...) so each is
  individually verifiable.
- **Priority** per requirement: `Demo-critical` (must work live), `Important` (strongly expected),
  `Stretch` (valuable, never blocking), or `Future-seam` (defined now, built later).
- "Configurable" means the value lives in one tuning type (`WatchTuning`, see the design), not
  hard-coded at call sites.
- Numbers marked **(verify)** are starting hypotheses to be measured on the owner's watch and the
  iPhone 14 before they are treated as promises.
- Cross-spec references say "rear-camera Req N / task N", "crash-response Req N / task N",
  "MVP task N", or "the demo-mode spec".

## Glossary

- **Wrist surface** — the Whoosh watchOS app: the rider's in-ride display, controls, and haptic
  actuator.
- **Phone-authoritative** — the ride (state machine, GPS, camera, crash workflow, persistence)
  lives only on the phone; the watch displays and requests, it never decides.
- **Wire contract** — the versioned set of messages exchanged over WatchConnectivity (envelope +
  payload types), defined once in a Foundation-only package both apps compile.
- **Live channel** — `sendMessage` (low latency, only while the counterpart is reachable, not queued).
- **Context channel** — `updateApplicationContext` (latest value only, delivered when possible).
- **Queue channel** — `transferUserInfo` (ordered, guaranteed delivery, possibly late).
- **Keep-alive session** — the `HKWorkoutSession` (cycling) the watch holds during a ride so the
  watch app keeps running with the wrist down and may play haptics in the background.
- **Command** — a rider-initiated request from the watch (pause, resume, saveClip, stop,
  cancelCrashCountdown, requestStart). **Reply** — the phone's typed answer including a fresh status.
- **Alert** — a one-shot event for the wrist (haptic + short text). **Notice** — an alert kept in a
  short on-watch log.
- **Cue** — one `WKHapticType` play. **Pattern** — a timed sequence of cues. **Tier** — urgency
  class: `critical`, `caution`, `notice`, `confirm`.
- **Armed ("Ready to ride")** — a phone state in which a watch may start the ride (Requirement 9).
- **Escalation** — when the watch does not confirm an alert in time, the fan-out also uses another
  channel (phone audio / notification).
- **Hold-confirm** — a deliberate press-and-hold (or equivalent) required before a destructive
  command; carried on the wire as `holdConfirmed`.

## Changed assumptions (recorded explicitly)

| ID | Earlier assumption | New assumption | Where it is superseded or reasoned |
| -- | ------------------ | -------------- | ---------------------------------- |
| W-A | rear-camera Req 13.2: **start is not a remote command in v1**; the ride is started and framed on the phone. | A watch may **request start**, but only while the phone is in an **armed** ready state (foreground, framed, rider-armed). iOS requires the foreground for camera and for starting When-In-Use location updates, so the phone must already be up. | Requirement 9; design "Start from the wrist"; open decision **O-W5**. Recorded as an amendment (Requirement 1.9). |
| W-B | rear-camera design capability row 11: continuous WatchConnectivity use is realistic only if the watch app keeps itself alive; "latency and battery are watch-spec concerns". | The watch holds a **cycling workout session** for the ride; reachability and haptics rely on it. Gated by a spike. Extended runtime sessions are **not** used (their types do not include cycling). | Requirement 4; design "Keep-alive"; open decisions **O-W2, O-W4**; task 1. |
| W-C | `product.md`: Smartwatch companion is "NOT in the MVP demo", a separate follow-up spec. | It is now specified here. It stays **opt-in and post-MVP**; the MVP and rear-camera flows are unchanged when no watch is present. | Requirement 1; `product.md` cross-reference (added by this job). |
| W-D | `privacy.md` lists no HealthKit use. | The watch app uses **HealthKit write-only for the workout type** (no reads) to hold the keep-alive session and optionally save the ride to Apple Health. Nothing is uploaded by Whoosh. | Requirements 4.5, 16, 19; design "Privacy"; open decision **O-W3**. |
| W-E | crash-response: the countdown is cancelled on the phone (tap). | The countdown is **also cancellable from the wrist**; the phone additionally speaks and shows it. A watch cannot guarantee it is seen. | Requirement 15; crash-response "Risks" row (already notes this). |
| W-F | rear-camera `AlertSink`: `deliver(kind, context)` is non-blocking with no result. | The sink may report an **outcome** (played / suppressed / failed / timed out) so the fan-out can escalate; `AlertContext` gains an id, urgency, TTL, and demo flag. Additive; the existing `AlertManager` protocol is unchanged. | Requirement 13; design "Seam amendments". |
| W-G | The phone's `LocalNotificationAlertSink` is the primary route to a locked phone's watch (rear-camera design). | With a **ready** watch the direct channel is primary; the notification becomes the escalation. (iOS routes a notification to the watch only when the iPhone is locked or asleep: Apple Support, **Checked**.) | Requirement 13.4. |

---

## Requirement 1: Scope, positioning, and non-goals

**Priority:** Demo-critical

**User story:** As a cyclist with a rear-mounted phone, I want my wrist to show what the ride is
doing and let me control it, without ever touching the phone.

### Acceptance Criteria

1. The system SHALL provide a watchOS companion app (the **wrist surface**) that offers: live ride
   time, distance, and speed; ride, camera, and phone-link state; pause, resume, press-and-hold stop,
   and "Save clip"; haptic alerts; and the crash-countdown Cancel.
2. The **phone SHALL remain authoritative.** The ride state machine, GPS, camera, crash workflow, and
   persistence SHALL live only on the phone. The watch SHALL display what the phone publishes and SHALL
   request changes through typed commands; it SHALL NOT record a ride, hold ride data, or decide a
   state transition.
3. WHEN no watch is present, paired, installed, or reachable THEN every phone flow SHALL behave exactly
   as defined in the MVP, crash-response, and rear-camera specs (audio cues through the phone, the
   ride-mode unlock gesture). The watch is additive.
4. A watch, link, workout-session, or haptic failure SHALL NEVER stop, pause, or corrupt the ride, GPS
   recording, or camera recording (Never block a ride).
5. The system SHALL NOT claim that the haptic cue is reliable detection, that it protects the rider from
   other road users, that a crash alert will be delivered, or that help is coming. Copy says the rear-vehicle cue
   is **experimental** and that Whoosh **cannot guarantee detection or delivery**; disclaimers SHALL be
   phrased to pass `scripts/privacy-check.sh` rule 4.
6. **Non-goals.** v1 SHALL NOT include: a standalone watch ride (no GPS recording on the watch); maps or
   routes on the watch; ride history on the watch beyond the last summary; health analytics; reading
   any HealthKit data; or support for non-Apple wearables (Requirement 23).
7. Every framework touchpoint (WatchConnectivity, HealthKit workout sessions, WatchKit haptics, watch
   notifications, UIKit on the phone) SHALL sit behind a protocol with a fake, per the existing layering
   table.
8. The watch app SHALL be **opt-out at any time** from the phone (Settings → Apple Watch): turning it off
   stops all watch traffic and the fan-out routes to phone channels only.
9. **Amendments.** This spec amends approved specs only through the recorded list in `design.md`
   ("Seam amendments to approved specs"). The approved documents are not edited by this spec's authoring
   job; a task (task 2) applies the named edits after owner approval.

## Requirement 2: Targets, versions, and project structure

**Priority:** Demo-critical

**User story:** As the iOS owner, I want the watch app to install on my Apple Watch SE and be buildable
and testable without adding project-file friction.

### Acceptance Criteria

1. The project SHALL gain a watchOS app target (**`WhooshWatch`**, SwiftUI, a companion of the iOS app,
   bundle identifier `com.whoosh.app.watchkitapp`, `WKCompanionAppBundleIdentifier` set to the iOS app).
   Its deployment target SHALL be **watchOS 10.0** (open decision O-W1): watchOS 10 pairs with iOS 17,
   which is the app's minimum, and every Apple Watch SE generation can run it (Apple compatibility
   table, **Checked** in `design.md`).
2. The system SHALL support the owner's SE **whichever generation it is**: SE (1st generation) runs up
   to watchOS 10.6.1; SE 2 and SE 3 run later releases. The owner SHALL identify the model in task 0
   (Apple Support "identify your Apple Watch model").
3. Code shared by both apps SHALL live in one **Foundation-only local Swift package**
   (`Packages/WhooshWire`): the wire contract, the codec, and the pure watch-side logic (reducers,
   freshness, haptic selection and limiting). It SHALL import no UIKit, SwiftUI, WatchKit, HealthKit,
   WatchConnectivity, CoreLocation, AVFoundation, or networking APIs, and SHALL be testable with
   `swift test` on a Mac without a simulator.
4. The watch target SHALL use the Swift 6 language mode. WatchConnectivity delegate callbacks SHALL hop
   to a defined actor before touching state; heavy work SHALL NOT run on the main actor.
5. The watch target SHALL follow the layering rule: views are thin and send intents to an `@Observable`
   model; no business logic and no direct framework call in a `View`.
6. Project and capability changes (the new target, the package reference, entitlements, background modes,
   Info keys) SHALL be made through `project.yml` and a one-time regeneration by the iOS owner; the
   committed `Whoosh.xcodeproj` remains the source of truth.
7. The watch app SHALL use only watchOS 10 APIs unconditionally. Any newer API (for example an optional
   double-tap shortcut) SHALL be availability-gated and optional.
8. The iOS deployment target and the iPhone-only device family SHALL NOT change.

## Requirement 3: Pairing, installation, and the pre-ride readiness screen (phone)

**Priority:** Demo-critical

**User story:** As a cyclist, I want to know before I mount the phone that my watch is connected and
that I can feel an alert.

### Acceptance Criteria

1. The phone SHALL provide an **Apple Watch** readiness screen, reachable from Home, from Settings, and
   from the Start-ride path when the watch is in use, showing a checklist with icon + text rows: watch
   paired; Whoosh watch app installed; link activated; watch reachable now; watch Health permission
   granted (as reported by the watch); watch battery; no other workout running on the watch; haptics test
   result; and reminders for Silent Mode, Theater Mode, Do Not Disturb, Water Lock, and watch haptic
   strength.
2. The screen SHALL NEVER hard-block the ride. A failing row SHALL explain the consequence in plain words
   ("Alerts will use the phone's audio instead") and SHALL offer the fix when one exists. "Ride without
   watch" is always available.
3. The screen SHALL include a **haptics test**: "Send test buzz" sends a test alert; the screen shows the
   watch's reply (played, suppressed with a reason, or no reply) and asks the rider to confirm "I felt it"
   or "I didn't". The result and its time SHALL be shown on the screen and in the Start path; three
   consecutive "I didn't" or no-reply results SHALL show a troubleshooting hint.
4. The screen SHALL include **Feel the patterns**: a list of the catalog patterns (Requirement 11) that
   the rider can play on the wrist one at a time. Previews SHALL be clearly labeled as previews, SHALL
   never start a crash countdown, and SHALL be available without demo mode.
5. IF the watch app is not installed or the watch is not paired THEN the screen SHALL show short, honest
   instructions (open the Watch app on the iPhone and install Whoosh) without claiming it can install the
   app, and SHALL keep the rest of the app unaffected.
6. The row logic SHALL be a pure, unit-tested `WatchReadinessEvaluator` (pass / warn / info) over facts
   from the link and the watch's reported state; the view model SHALL be driven by it.
7. The screen SHALL work in airplane mode and offline (the link is device to device).
8. "Apple Watch alerts and controls" in Settings SHALL default **on** when a Whoosh watch app is detected
   and SHALL be switchable off (Requirement 1.8); switching it off SHALL stop watch traffic immediately.
9. The screen SHALL show the watch's reported battery when known and SHALL warn below a configurable level
   (default 40%) before a ride and the watch app SHALL report a low-battery notice during a ride
   (Requirement 14).
10. The screen SHALL NOT request any system permission, except that IF the owner-approved device check
    shows that `startWatchApp` needs HealthKit authorization on the phone THEN that request SHALL occur
    only when the rider first enables the watch, after an in-app explanation (Requirement 19.8).

## Requirement 4: Keeping the watch app alive during a ride

**Priority:** Demo-critical (gated by the spike, task 1)

**User story:** As a cyclist, I want the wrist alerts to work with my wrist down and the watch screen off.

### Acceptance Criteria

1. WHILE a ride is active THE watch app SHALL hold one active **`HKWorkoutSession`** (activity type
   cycling) so that it keeps running with the wrist lowered, stays reachable to the phone, and may play
   haptics in the background (Apple reference pages, **Checked**; behavior on the owner's watch
   **(verify)**, task 1).
2. The system SHALL NOT use a `WKExtendedRuntimeSession` for this purpose: its session types (self care,
   mindfulness, physical therapy, smart alarm) do not cover cycling, Apple tells strenuous activities to
   use a workout session, and misuse risks App Review rejection (**Checked**).
3. The session SHALL start by one of three paths, all ending in the same session logic: (a) the phone
   starts a ride and asks the watch app to start (`HKHealthStore.startWatchApp(with:)`, handled in the
   watch delegate's workout-configuration handler); (b) the rider opens the watch app while a ride is
   active, and the app starts the session automatically (Apple's companion-coordination guidance,
   **Checked**); (c) the rider starts the ride from the wrist (Requirement 9).
4. The workout session SHALL **follow the ride** (phone-authoritative): ride `recording` or `signalLost`
   → session running; `paused` → session paused **(verify that a paused session keeps the app alive; if
   not, keep it running and mark the pause with a workout event)**; `idle` / `finished` → session ended.
   Ending the ride anywhere SHALL end the watch session without a second rider action, which satisfies
   Apple's guidance that a workout started on one device must not keep running on the other.
5. The watch app SHALL request HealthKit authorization **only to share the workout type** and SHALL read
   nothing. It SHALL ask when the rider first starts a watch-supported ride or first taps "Set up watch
   alerts", after an in-app explanation. Denial SHALL leave the watch app usable in the foreground and
   SHALL be reported to the phone so the fan-out uses audio (Requirement 13).
6. The watch target SHALL declare the **Workout processing** background mode; whether the **Audio** mode
   is also required for haptics, as Apple's page states for apps that "play audio or provide haptic
   feedback", SHALL be settled in task 1 **(verify)** and the minimum SHALL be declared.
7. The session SHALL be **honest and visible**: the watch app SHALL clearly show that a workout session
   is in progress, and the end-of-ride flow SHALL satisfy Requirement 16.
8. IF another workout starts on the watch THEN the session SHALL end with
   `errorAnotherWorkoutSessionStarted` (Apple: the watch runs one workout session at a time, **Checked**);
   the watch app SHALL report it to the phone, the phone SHALL stop treating the watch as haptics-ready,
   and the rider SHALL be told through the audio channel and on the watch.
9. WHEN the watch app relaunches during a ride after a crash THEN it SHALL recover the active workout
   session (`recoverActiveWorkoutSession`) and re-sync with the phone.
10. The session's `locationType` SHALL be set by owner decision **O-W4** (recommended: not outdoor
    tracking), the watch app SHALL NOT request location authorization, and the watch SHALL NOT read or
    send GPS data.
11. The system SHALL bound watch work while the session runs (no per-second heavy CPU; the clock is
    ticked locally from an anchor) and SHALL be measured against the budgets in Requirement 22; it SHALL
    make no battery-life claim before measurement.
12. IF the session cannot be started or is lost THEN the watch SHALL fall back to foreground-only
    operation, SHALL tell the phone (`WatchState`), and the rider SHALL be told (never silent).

## Requirement 5: Communication channels and the wire contract

**Priority:** Demo-critical

**User story:** As the team, I want phone and watch to exchange a small, versioned, testable contract
that survives app updates and dropped connections.

### Acceptance Criteria

1. The link SHALL use **WatchConnectivity** with: `sendMessage` for live, low-latency events and
   commands while reachable; `updateApplicationContext` for the latest status; and `transferUserInfo`
   for must-arrive items. It SHALL NOT use file transfer, a server, or a third-party channel in v1.
   (An HKWorkoutSession-mirroring data channel is documented as an alternative and fallback, open
   decision O-W10, spike-evaluated only.)
2. Message types SHALL be assigned to channels exactly as the design's channel table states; in
   particular, **commands and alerts are never queued for later delivery** (except the single, guarded
   crash-cancel exception in Requirement 6.6), and **status is latest-wins**.
3. Every message SHALL be a property-list dictionary containing an **envelope** — protocol version `v`,
   `type`, message `id` (UUID), per-session `seq`, `sentAt` (sender clock, for logs and age estimates
   only), and optional `ttlMs` — and a payload encoded as deterministic JSON `Data`. The payload SHALL
   contain enums, numbers, booleans, and identifiers only; **no free-form text** (Requirement 19).
4. **Versioning.** Each side SHALL send a `hello` with its supported version range; the link SHALL
   negotiate the highest common version. Changes within a version SHALL be additive only. Unknown
   payload fields SHALL be ignored; unknown enum values SHALL decode to a safe `unknown` case that is
   handled (an unknown alert kind plays the generic notice cue); an unsupported major version SHALL
   produce a typed rejection and a calm "Update Whoosh on your watch / phone" message, never a crash.
   A current release SHALL support the immediately previous wire version.
5. Decoding SHALL be strict and total: bad input returns a typed error and is dropped, never a crash
   (the spike's reject-bad-input checks are the model).
6. Message size SHALL stay within the budgets in the design (**verify** the practical limits); status
   SHALL be rounded (distance to 10 m, speed to 0.1 m/s) to keep it small and to avoid false precision.
7. WHEN a live send fails because the counterpart is not reachable THEN the sender SHALL surface the
   failure immediately to its caller (typed result), SHALL NOT silently re-route a command or alert to a
   queue, and SHALL leave fallback decisions to the fan-out / UI.
8. Both sides SHALL activate the session at launch, handle re-activation after the phone-side session
   deactivates, and on the watch SHALL complete every WatchConnectivity background task (an uncompleted
   task consumes the app's background budget and can crash the app: Apple sample, **Checked**).
9. **Ordering and dedupe.** Status carries a monotonic `seq` within a ride `epoch`; receivers ignore
   `seq` at or below the last accepted for that epoch. Alerts and commands carry unique ids; receivers
   keep a bounded recent-id cache so a duplicate or replayed message has no second effect.
10. The link SHALL be an explicit pure **state machine** (`unsupported`, `notPaired`, `notInstalled`,
    `activating`, `inactive`, `installedUnreachable`, `reachable`, `ready(peer)`, `incompatible`)
    with the transitions in the design; undefined transitions SHALL be no-ops.
11. The link SHALL sit behind a `WireLink` protocol with a fake and a **loopback pair** that can add
    delay, drop, duplicate, reorder, and unreachable periods, so all behavior is testable without
    devices (WatchConnectivity transfers must be tested on paired devices, and the simulator does not
    support `transferUserInfo`: **Checked**).

## Requirement 6: Wrist commands

**Priority:** Demo-critical

**User story:** As a rider, I want pause, resume, save-clip, and stop to do exactly what I asked,
once, and to know whether they worked.

### Acceptance Criteria

1. The watch SHALL be able to send these typed commands: `pause`, `resume`, `saveClip`, `stop`
   (carrying `holdConfirmed`), `cancelCrashCountdown` (carrying `crashEventId`), and `requestStart`
   (Requirement 9). Every command carries a `commandId` (UUID), the target `rideId` (absent for start),
   and `issuedAt`.
2. Commands SHALL be **idempotent by id**: the phone caches recent command ids (default 5 minutes or 128
   entries) with their replies; a repeated id returns the cached reply and has no second effect.
3. Commands SHALL be **state-based, not toggles** (`pause` and `resume` are separate); the reply SHALL
   include the outcome and a fresh status snapshot, so the watch resolves any ambiguity from the reply
   rather than guessing.
4. A command whose `rideId` does not match the active ride SHALL be ignored with reason `staleRide`
   (a delayed `stop` can never end a new ride).
5. The watch SHALL retry a command with the **same id** up to 3 attempts within its TTL (default 8 s) and
   SHALL then show "Not confirmed" and reconcile from the next status; it SHALL NOT re-issue with a new
   id automatically.
6. Control commands SHALL NOT be queued for later delivery. **Single exception:** `cancelCrashCountdown`
   MAY also be sent through the queue channel because it expresses "I'm OK", is guarded by
   `crashEventId` and the crash state machine, and a late arrival is safely ignored (Requirement 15.6).
7. **Confirmation levels** (open decision O-W11): `stop` requires a press-and-hold of about 1.0 s with
   visible progress, where release before completion cancels with no effect, plus a VoiceOver custom
   action; `requestStart` requires a hold of about 0.8 s; `pause`, `resume`, and `saveClip` are single
   taps; `cancelCrashCountdown` is a single tap on a control at least 80 pt tall (crash-response D12).
   A Digital Crown confirm is a Stretch alternative.
8. The watch SHALL show a pending state for each in-flight command, SHALL disable duplicates, and SHALL
   give local haptic feedback only after the **reply** (not optimistically): a light confirm for accepted,
   a failure cue for rejected or not confirmed.
9. WHEN the phone is unreachable THEN the controls SHALL be visibly disabled within 1 s with a short reason
   ("iPhone not responding") rather than appearing to work.
10. Distinct commands SHALL be separated by at least 500 ms on the watch; `saveClip` SHALL also be
    debounced on the phone (rear-camera Req 6.6, default 2 s).

## Requirement 7: Phone-side command handling (`RideRemoteControl`)

**Priority:** Demo-critical

**User story:** As the owner, I want a command from the wrist to obey exactly the same rules as a tap on
the phone.

### Acceptance Criteria

1. A `WatchRideRemote` SHALL implement the rear-camera `RideRemoteControlling` seam over `WireLink`;
   commands SHALL reach the ride only through the rear-camera `RideRemoteBridge`, which calls the
   **existing** `RideSessionViewModel` intents (`pause`, `resume`, `stop`), the clip pinner, and the
   crash coordinator. The ride engine SHALL NOT be modified.
2. A pure **`RemoteCommandReducer`** SHALL decide each command from (ride state, camera state, crash
   state, arming state, command, dedupe cache, protocol version) and SHALL produce a typed outcome
   (`accepted`, `alreadyInState`, `ignored(reason)`, `rejected(reason)`) plus effects as data. Its
   validity table SHALL be identical to the phone UI's rules (pause only from `recording` /
   `signalLost`, resume only from `paused`, stop only while active, per the MVP transition table).
3. Remote commands and phone-UI intents SHALL be **serialized on the main actor** in arrival order; any
   conflict SHALL be resolved by the same state guards (a tap on the phone and a command from the wrist
   at the same instant cannot both change state).
4. `stop` SHALL be accepted only with `holdConfirmed == true`, a matching `rideId`, and an active ride
   (rear-camera Req 13.2). WHEN a stop is accepted THEN ride mode SHALL restore brightness and the idle
   timer before the summary appears (rear-camera Req 10.7).
5. `saveClip` SHALL reply `saved`, `pending` (post-roll running), `nothingToSave`, `storageFull`, or
   `cameraOff`, never silence (rear-camera Req 6.7).
6. `cancelCrashCountdown` SHALL be accepted only while the crash event with that `crashEventId` is in
   `countdown`, through the coordinator's rider-cancel; the reply SHALL report the **true** outcome,
   including `tooLate` when expiry won the tie (crash-response transition row 9) and `notCancellable`
   when a send is in flight (row 18). It SHALL never be gated by consent state.
7. Unknown commands, unsupported versions, and malformed envelopes SHALL return a typed rejection and
   SHALL NOT affect the ride.
8. Command outcomes SHALL be recorded locally as counts and reasons (no user data) for a diagnostics view;
   nothing SHALL be uploaded.
9. A failure in the remote layer SHALL leave recording, GPS, camera, and the crash workflow unaffected.

## Requirement 8: Live ride status on the wrist

**Priority:** Demo-critical

**User story:** As a rider, I want to glance at my wrist and see the three numbers and whether the ride
and the camera are healthy.

### Acceptance Criteria

1. The watch Ride page SHALL show **at most three numbers**: elapsed ride time (large), distance (miles),
   and speed (mph) — matching the phone's three-number rule — plus state chips (icon + text, never colour
   alone): ride (Recording / Paused / Signal lost), camera (Recording video / Camera interrupted / Camera
   stopped / Camera off, or none when the camera feature is off), and, when needed, phone link.
2. Elapsed time SHALL be projected **locally** from the duration-at-send and the watch's own monotonic
   clock at receipt (no subtraction of phone and watch wall clocks), frozen while paused, by a pure
   `ElapsedTimeProjector`.
3. Units SHALL be US customary on the watch; the wire carries SI. Conversion and formatting SHALL live in
   one formatting layer.
4. Banners SHALL map from enums to short app-controlled copy: signal lost (amber), location permission
   revoked, storage low, phone warm, phone battery low. No raw framework text.
5. The phone SHALL publish status through `StatusTransportPolicy`: on change, plus a heartbeat (default
   5 s) while the watch display is active and a slower heartbeat (default 30 s) when it is not, using the
   **context** channel for the slow path; on wrist raise the watch SHALL request a fresh status and show
   "Updating…" until it arrives.
6. Status that is stale beyond a threshold SHALL be shown as stale (Requirement 10.4), never as live.
7. WHEN no ride is active THE watch Home page SHALL show readiness, the Start affordance when armed
   (Requirement 9), and the last ride's summary (Requirement 16), and nothing implying a ride is running.
8. The Ride page SHALL support reduced-luminance (wrist-down) presentation by showing only elapsed time and
   state glyphs, and SHALL respect the system always-on behavior on watches that have it.

## Requirement 9: Starting a ride from the wrist (amends rear-camera 13.2)

**Priority:** Important (Tier 1/2)

**User story:** As a cyclist, I want to mount the framed phone, walk to the front of the bike, and start
the ride from my wrist.

### Acceptance Criteria

1. The phone SHALL offer **"Ready to ride — start from watch"** on the readiness / Mount & frame path.
   Only the rider's tap on the phone puts the phone in the **armed** state; a watch can never arm it.
2. WHILE armed THE phone SHALL stay in the foreground with the idle timer disabled (through the screen
   controller) and MAY use the ride-mode dim after a short delay; it SHALL show a clear armed screen with
   "Cancel". Arming SHALL expire (default 5 minutes, range 1–15), when the app leaves the foreground, or
   when the rider cancels; expiry SHALL be shown on the watch and the phone.
3. `requestStart` SHALL be accepted only WHEN: the phone is armed; the ride state is `idle`; location is
   authorized; IF rear camera recording is enabled THEN framing was completed and no readiness **block**
   row (rear-camera Req 9.3) is failing; no crash event is active; and the watch link is `ready`.
   Otherwise the reply SHALL carry a typed reason that the watch renders as a short instruction ("Tap
   Ready on your iPhone").
4. The Start control on the watch SHALL appear enabled only when the status reports `armed`, and SHALL
   require a press-and-hold of about 0.8 s.
5. WHEN a start is accepted THEN the phone SHALL perform exactly the action of its own Start button, with
   `startedFromWatch` set so the mount-grace countdown is skipped or shortened (the phone is already
   mounted), the camera starts, and ride mode begins; the reply SHALL carry the new `rideId`.
6. The watch SHALL start its keep-alive session when it sees the ride become active, and SHALL report
   `WatchState` back; a failed session start SHALL be announced (Requirement 4.12).
7. The system SHALL document exactly what the watch can and cannot do when the phone app is not in the
   foreground (Requirement 10); in particular **the watch cannot start a ride when the phone app is not
   running in the foreground in the armed state**, because the camera and the start of When-In-Use
   location updates need the foreground (rear-camera design, **Checked** there).
8. A started-from-wrist ride SHALL be indistinguishable in storage and summary from a phone-started one.

## Requirement 10: When the phone app is not running; link loss; reconnect

**Priority:** Demo-critical

**User story:** As a rider, I want the watch to be honest about what it can do when the phone is gone,
and to recover on its own when it returns.

### Acceptance Criteria

1. The design SHALL include a normative matrix of **phone app state × watch capability** (not
   installed, not running with no ride, foreground idle, foreground armed, ride active, ride active but
   the phone app was terminated). The watch SHALL implement exactly it; no control SHALL appear usable
   when the matrix says it is not.
2. `sendMessage` from the watch wakes the phone app in the background only if the phone app is
   reachable; **a force-quit or terminated phone app is not relaunched by the watch**, and a ride cannot
   be started from the background (Apple: calling `sendMessage` from the watch wakes the iOS app; calling
   it from the iPhone does not wake the watch app: **Checked**; relaunch behavior after force-quit
   **(verify)**, task 1).
3. WHEN the watch app is not running THEN the phone cannot message it; the phone SHALL be able to ask the
   system to start it for a ride (`startWatchApp`) and, during an active ride with a missing watch
   session, SHALL retry that request with backoff (default up to 3 times, 15 s apart) and report the
   outcome in the channel state.
4. **Staleness.** WHEN no message arrives for longer than the staleness threshold while the display is
   active THEN the watch SHALL mark status stale (dim the numbers, label elapsed time "est.", replace
   state chips with "iPhone not responding"), disable commands, and play the link-lost notice once.
5. WHEN the link is lost during an active ride for more than 20 s THEN the phone SHALL announce
   "Watch disconnected" through its audio channel, and the watch SHALL announce its own link loss; each
   side announces what it can no longer confirm (camera trouble is never silent).
6. WHEN the phone has been silent for 60 s during a ride the watch last saw as active THEN the watch SHALL
   say "iPhone app may have closed. Open Whoosh on your iPhone to recover your ride", and SHALL NOT claim
   the ride is still recording. The watch session SHALL continue until the rider ends it or an orphan
   timeout (default 15 minutes) ends it with a notice.
7. **Reconnect.** WHEN reachability returns THEN both sides SHALL exchange `hello`; the phone SHALL send a
   full status, the current crash countdown if one is active, and any unread notices; the watch SHALL
   send `WatchState`. Missed fresh-alert events SHALL NOT be replayed as haptics; persistent states
   (camera stopped, signal lost) SHALL be shown from status without a new buzz unless newer than their TTL.
8. WHEN a new ride starts THEN the status `epoch` SHALL change and the watch SHALL discard all state tied
   to the previous ride.
9. The channel state SHALL be exposed to the routing policy so that when the watch is not `ready` the
   fan-out uses phone channels from the start, not after a timeout.
10. Transitions SHALL be unit-tested with the loopback link (drop, delay, duplicate, reorder, unreachable
    windows) and verified on devices (task 28).

## Requirement 11: Haptic alert catalog

**Priority:** Demo-critical

**User story:** As a rider, I want different things to feel different, and I want the most important
ones to be unmistakable.

### Acceptance Criteria

1. The system SHALL define a **catalog** mapping each alert event to a **tier** and a **pattern** — a
   timed sequence of `WKHapticType` cues (the only haptic values the platform exposes: notification,
   directionUp, directionDown, success, failure, retry, start, stop, click, and the navigation cues;
   **Checked**) — covering at least: crash countdown (start, repeat, cancelled, too late, ended), rear-
   vehicle cue (two levels), camera interrupted / resumed / stopped, clip saved / not saved, phone
   battery low (two levels), phone link lost / restored, ride started / paused / resumed / stopped, and
   command not confirmed.
2. Tiers SHALL be `critical` (crash countdown), `caution` (rear-vehicle cue, camera stopped, battery
   critical), `notice` (camera interrupted, clip not saved, battery low, link lost), and `confirm`
   (acknowledgements). A higher tier SHALL preempt a lower one; a lower tier SHALL be dropped if a higher
   one is playing.
3. **Distinctness.** No two catalog entries with different meanings SHALL share the same cue sequence and
   timing; the three most important patterns (crash countdown start, rear-vehicle cue, camera stopped)
   SHALL differ in first cue, count, or timing. A pure test SHALL assert uniqueness; the rider-facing
   judgement is made on the wrist in task 19 (spike test T1).
4. Cues SHALL be used for their documented purposes where possible and SHALL NOT be used to mislead (for
   example, never `success` for a bad event). Where no cue fits, the choice and its limits SHALL be
   recorded in the design (open decision O-W6).
5. Patterns SHALL be data (a list of cue + delay steps) produced by a pure `HapticPatternSelector` from
   (event, tier, level); the watch maps cue names to `WKHapticType` at the playing layer only.
6. Consecutive cues inside a pattern SHALL be spaced at least 100 ms apart (the platform imposes a minimum
   delay and cancels a cue in progress when a new one is requested: **Checked**), and the design default
   SHALL be 300–500 ms so each cue is felt separately.
7. The rear-vehicle cue SHALL be labeled **experimental** in any text accompanying it (for example
   "Vehicle cue (experimental)") and SHALL NOT say "warning", "collision", or "danger".
8. Patterns SHALL be playable only from an active app state; the playing layer SHALL check the watch app
   state and SHALL report `suppressed(notActive)` rather than failing silently (WatchKit: `play(_:)` has no
   effect in background / inactive states except with an active workout session: **Checked**).
9. The catalog SHALL be tunable in one place and SHALL be previewable on the wrist (Requirement 3.4).

## Requirement 12: Rate limiting and cooldown layering

**Priority:** Demo-critical

**User story:** As a rider in traffic, I never want my wrist spammed, and I never want a real event
hidden.

### Acceptance Criteria

1. The system SHALL layer limits as follows and SHALL NOT bypass any upstream layer: **L0** the
   rear-vehicle gate (`RearAlertGate`: delivered only while a ride is `recording` and speed exceeds the
   configured threshold, default 2 m/s; defined by the demo-mode spec) — unchanged and upstream of
   `AlertManager`; **L1** the phone audio/haptic sink's own cooldown (`AlertCooldown`, default 2 s, in
   `HapticAudioAlertManager`) — unchanged, applies to that sink only; **L2** the fan-out's
   `AlertRoutingPolicy` cooldowns (rear-vehicle caution at most once per 3 s; camera notices at most once
   per minute per reason: rear-camera design) — applies to all sinks including the watch; **L3** the
   watch's `WristHapticLimiter`.
2. The `WristHapticLimiter` (pure, Foundation-only, on the watch) SHALL enforce: a minimum gap between
   pattern starts (default 1.0 s); the platform's 100 ms minimum between cues; per-kind cooldowns that
   mirror L2 (so a replayed or duplicated message cannot double-buzz); and a **storm backoff** for the
   rear-vehicle cue — consecutive cues within 30 s lengthen the cooldown 3 s → 6 s → 12 s, resetting after
   30 s of quiet.
3. A suppressed cue SHALL be counted and reported (`alertReceipt`), shown in the ride summary as a count
   ("N cues"), and SHALL NEVER be silently discarded without a record.
4. **Freshness.** Alerts carry a TTL (defaults: rear-vehicle 3 s, clip notices 10 s, camera and battery
   notices 30 s, link notices 20 s; crash alerts until the countdown deadline). The watch SHALL drop an
   alert whose estimated age exceeds its TTL and report `suppressed(stale)`; a backlog after a delay
   SHALL NOT replay a burst of old cues.
5. **Dedupe.** An alert id seen before SHALL have no second effect.
6. **Demo bypass.** A demo-forced rear-vehicle alert (which bypasses L0 only) SHALL pass through L2 and L3
   like any other, SHALL carry `isDemo`, and the watch SHALL play a demo-flagged alert only while the
   phone reports demo mode active and SHALL label it DEMO.
7. The limiter and freshness logic SHALL be pure and unit-tested with a controllable clock.

## Requirement 13: Alert fan-out and sinks

**Priority:** Demo-critical (watch + phone audio); Future-seam (external Bluetooth device)

**User story:** As a rider, I want an alert to reach me by the best available channel, and to fall back
automatically when that channel does not confirm.

### Acceptance Criteria

1. The system SHALL provide a **`WatchAlertSink`** (an `AlertSink`) that encodes the alert, sends it on the
   live channel with a reply, and reports an outcome (`played`, `suppressed(reason)`, `failed(reason)`,
   `timedOut`). Existing sinks (phone audio, phone haptic when ride mode is off, local notification) and
   the unchanged `AlertManager` protocol are retained.
2. `AlertRoutingPolicy` (pure) SHALL receive the **channel states** (watch `ready` / `degraded` /
   `unavailable`, audio available, notification authorized, phone locked, ride-mode on) and SHALL return an
   ordered plan with timeouts. With the watch `ready`, the plan for a `caution` or `critical` alert is
   watch first, then escalation to phone audio when the watch does not confirm within the **watch
   acknowledgement timeout** (default 1.5 s). With the watch not `ready`, the plan starts on phone
   channels.
3. Audio SHALL NOT play concurrently with a confirmed watch haptic for the rear-vehicle cue by default
   (wind noise, headphone-use rules vary by place, and double cues are noise); a Settings option "Also
   play a sound" (default off) MAY enable it (open decision O-W7). The crash countdown SHALL always use
   all channels (rear-camera table).
4. The local notification SHALL be the **escalation**, not the primary, when the watch is `ready`; with the
   phone locked and the watch unreachable it remains the primary (it mirrors to the watch because the
   phone is locked: **Checked**).
5. Sinks SHALL be non-blocking; a failing sink SHALL NOT affect recording, other sinks, or the ride.
6. `AlertContext` SHALL carry an alert id, urgency tier, TTL, demo flag, and optionally a coarse
   confidence and a position hint (left / center / right) — additive to the approved seam.
7. The sink SHALL report the watch's reply to the fan-out so the policy can escalate; the outcome tracker
   SHALL be a pure state machine (alert id → pending / confirmed / escalated / expired).
8. **Future Bluetooth device.** The seam SHALL allow an `ExternalHapticSink` (the vibration proposal's
   option D: a handlebar or glove device) to register as another channel with its own availability and
   reliability, without changes to the fan-out or the wire contract. No Bluetooth code or permission is
   added by this spec (Requirement 23).
9. New `AlertKind` cases needed for the link (`watchDisconnected`, `watchReconnected`) SHALL be additive
   and SHALL be routed to phone channels only.

## Requirement 14: Notices (clip saved, camera, battery, link)

**Priority:** Important

**User story:** As a rider, I want to be told, on my wrist, when the camera stops, when a clip is saved,
and when the phone battery is low.

### Acceptance Criteria

1. The following SHALL reach the wrist as alerts with their catalog pattern and a short text: clip saved,
   clip not saved (with reason), camera interrupted (with reason), camera resumed, camera stopped (with
   reason: thermal, storage, battery, permission, failed), and phone battery low (two levels).
2. Camera trouble SHALL NEVER be silent (rear-camera Req 17.1): WHEN the watch is not `ready` THEN the
   announcement SHALL use phone audio, and the ride summary SHALL record the gap in every case.
3. The watch SHALL keep a **notice log** of the last 10 alerts (kind, time-into-ride, reason code) in
   memory for the current ride, viewable on a Notices page; unread notices SHALL show a badge. The log
   SHALL be discarded when the next ride starts and SHALL NOT be persisted across ride end.
4. A persistent degradation (camera stopped, signal lost) SHALL remain visible as a state chip until it
   clears, with at most one reminder haptic per minute per reason while unacknowledged, up to two
   reminders (rear-camera cooldown), and acknowledging on the watch SHALL stop reminders.
5. Must-arrive notices SHALL also be sent on the queue channel with their original time so a watch that
   reconnects shows them in the log as past events without buzzing.
6. The watch SHALL report its own **battery low** (default ≤ 15%) and workout-session loss to the phone
   (`WatchState`); the phone SHALL announce them through its channels.
7. Notice text SHALL be short, app-controlled, localized in one place, and SHALL pass the honest-copy
   rules.

## Requirement 15: Crash countdown on the wrist

**Priority:** Important

**User story:** As a rider whose phone is on the bike, I want to cancel a false crash alert from my
wrist.

### Acceptance Criteria

1. WHEN the crash coordinator starts a countdown THEN the phone SHALL publish the countdown (event id,
   absolute deadline, drill flag, number of contacts) in status and send a `critical` alert on the live
   channel; the watch SHALL play the countdown pattern and present a full-screen takeover above every
   page.
2. The takeover SHALL show: "Crash detected" with an icon; the remaining seconds computed from the
   **absolute deadline**; "Sending an alert to N contact(s) in S s" (**a count only: contact names and
   numbers are never sent to the watch**); a full-width **"I'm OK — Cancel"** control at least 80 pt tall;
   and the short disclaimer "Not an emergency service. Can't guarantee detection or delivery." with the full
   crash-response text on a scrollable "More" area. It SHALL NOT offer "Send now" or "Call 911" (those
   remain phone actions).
3. **Drills** (crash-response `drill` template, started from demo mode) SHALL be labeled **"DEMO — NOT
   REAL"** on the takeover and in the haptic text, and the watch SHALL treat them as drills only when the
   phone reports demo mode.
4. A Cancel tap SHALL send `cancelCrashCountdown` and show "Cancelling…" until the reply; the watch SHALL
   show "Cancelled" only when the reply says so, "Too late — the alert is sending" when expiry won, and a
   clear "Couldn't reach iPhone — tap again" with automatic retries once per second (same command id)
   until the deadline when the link fails.
5. The phone SHALL always run its own audible / visual countdown and ride mode SHALL exit to full
   brightness and unlock (rear-camera Req 13.7); the watch is an **additional** cancel path, not a
   replacement. Consent copy (crash-response) SHALL say the watch cannot guarantee that it is seen or that
   a cancel arrives.
6. `cancelCrashCountdown` MAY be sent on the queue channel in addition to the live channel; the phone
   ignores it unless the same `crashEventId` is in `countdown` or `queuedOffline` (crash-response rows 7,
   21), so a late arrival is harmless.
7. WHEN the countdown ends THEN the watch SHALL reflect the phase (sending, sent, queued offline, cancelled)
   from status with plain copy ("Alert sent. Delivery is not guaranteed"), never "help is coming".
8. As a **backup** for a dark watch screen, the watch app MAY schedule a local time-sensitive notification
   with an "I'm OK — Cancel" action when a countdown starts (open decision O-W8); the iPhone's own backup
   notification does not reach the watch while the phone is unlocked (**Checked**). Notification
   authorization on the watch SHALL be requested only when crash alerts are enabled and the watch is used,
   after an in-app explanation.
9. WHEN the watch screen is off at countdown start THEN the haptic SHALL play (workout session) and the
   design SHALL state honestly that the app cannot wake the display; the audible phone countdown remains.
10. Reduce Motion SHALL produce a static high-contrast takeover; there SHALL be no flashing.

## Requirement 16: End of ride, summary, and saving to Apple Health

**Priority:** Important

**User story:** As a rider, I want a clear end to the ride on my wrist and control over whether it is saved
to Health.

### Acceptance Criteria

1. WHEN the ride ends (anywhere) THEN the watch SHALL show a **summary** (time, distance, average speed,
   count of notices) delivered on the queue channel, and SHALL end the keep-alive session.
2. The watch SHALL offer **Save to Health** and **Discard** (Apple: a workout app must either save
   automatically or provide a clear save/discard option: **Checked**). The default is the persisted
   setting (open decision O-W3, recommended: Save), applied after 60 s without a choice so the session does
   not drain the battery while waiting.
3. A saved workout SHALL contain only what the system collects for a cycling session; Whoosh SHALL NOT
   write route, location, distance, camera, or clip data to Health in v1, and SHALL NOT read any Health
   data.
4. The watch SHALL show clear feedback when a workout is saved or discarded, and plain copy about it
   ("Saved to Apple Health on your devices").
5. The saved ride on the phone SHALL be unaffected by the watch choice.
6. IF the session ended because another workout started or the app was lost THEN the summary SHALL say so
   and SHALL NOT claim a saved workout that does not exist.
7. The summary SHALL NOT include location, a route, or contact data.

## Requirement 17: Complications and Smart Stack

**Priority:** Stretch

**User story:** As a rider, I want to see the ride time from the watch face and jump into the app.

### Acceptance Criteria

1. A WidgetKit complication / Smart Stack widget MAY show a running ride timer and the ride state, using a
   system-rendered timer driven by an anchor (no per-second updates) and a deep link into the app.
2. It SHALL be **opt-in** ("Show ride on the watch face", default off), because it displays on a possibly
   locked watch; it SHALL show only time and state, never distance, speed, location, or crash information.
3. Updates SHALL respect platform budgets; the queue-based complication transfer is limited to 50 per day
   **(Checked)** and SHALL NOT be the main update path.
4. The complication SHALL NOT be required for any function; its absence changes nothing.
5. Live Activities appearing in the Smart Stack on newer watchOS releases are out of scope and **(verify)**
   not available on watchOS 10.

## Requirement 18: Accessibility and wrist UX

**Priority:** Important

**User story:** As any rider, I want the wrist app to be usable with VoiceOver, large text, gloves, and
wet fingers.

### Acceptance Criteria

1. All controls SHALL have accessibility labels and traits; state SHALL be icon + text, never colour alone.
2. Stop SHALL have a VoiceOver custom action ("Stop ride") that does not require the timed hold, matching
   the phone's `HoldToStopButton`.
3. Primary controls SHALL be large (pause / resume and save clip at least 60 pt; Cancel at least 80 pt;
   verify that the layout fits the smallest supported case size) and the Ride page SHALL be readable at the
   larger Dynamic Type sizes without truncating the three numbers (numbers use a fixed scale like the
   phone's ride metrics; surrounding text scales).
4. VoiceOver SHALL announce state changes (paused, resumed, camera stopped, countdown start) and the
   countdown at start, every 10 s, and the last 5 s (crash-response Req 18.3).
5. Haptics SHALL NEVER be the only signal: every alert has text, and the phone speaks or sounds the same
   important events.
6. A stop SHALL be possible when touch is unreliable (wet or gloved): hold has a generous tolerance for
   finger movement; a Digital Crown confirm is a Stretch alternative; Water Lock disables touch and the
   readiness screen reminds the rider.
7. The watch theme SHALL reuse the brand tokens (Ink, Lime, Amber, Alert, Mist), a dark ride presentation,
   and tabular numerals.
8. Controls SHALL be reachable with the watch on either wrist and with the crown on either side (the
   system's orientation setting is honored); no gesture other than tap, hold, scroll, and crown is required.

## Requirement 19: Privacy and data minimization

**Priority:** Demo-critical

**User story:** As a rider, I want to be sure my location, video, and contacts do not go anywhere I did
not expect.

### Acceptance Criteria

1. The watch SHALL receive **no coordinates, route, map data, video, frame, thumbnail, clip id, contact
   name, contact number, or message text**. It SHALL receive only: ride state; elapsed duration; distance
   and speed (rounded); camera state and reason codes; battery percentages; counts; the crash countdown
   (event id, deadline, drill flag, contact **count**, phase); and alert kinds and codes.
2. A pure **payload allowlist test** SHALL serialize every wire type and fail on any field outside an
   explicit allowlist or any string longer than a short code (no free text).
3. Nothing SHALL leave the user's own devices because of this spec: the link is device to device through
   WatchConnectivity, the watch app makes **no network requests**, and the watch target SHALL contain no
   networking API, analytics, or tracking SDK (enforced by `scripts/privacy-check.sh`, extended to cover
   `WhooshWatch/` and the package).
4. The watch SHALL store: its settings (default-save-to-Health, optional "also play sound" mirror, optional
   complication opt-in), the last ride summary (counts and totals), and the notice log for the current ride
   (in memory only). It SHALL NOT persist status snapshots or alert history beyond the current ride.
5. HealthKit use SHALL be write-only for the workout type; Whoosh SHALL NOT read Health data and SHALL NOT
   upload any workout; the workout lives in Apple Health under the rider's own settings.
6. The status published to the watch SHALL be treated as visible to someone looking at the rider's wrist;
   therefore crash details beyond the countdown, and any location, SHALL NOT appear, and the complication is
   opt-in (Requirement 17.2).
7. `privacy.md` and `tech.md` SHALL be updated by task 2 (proposed text in the design) to add: the watch
   target, WatchConnectivity and HealthKit confined to named folders, the new permission rows, and the
   wire privacy rule.
8. Permission strings SHALL be purpose-specific, requested lazily, and honest: HealthKit share
   (watch): "Whoosh uses a cycling workout so haptic alerts keep working with your wrist down, and can
   save your ride to Apple Health when you choose." (final copy in task 29). No new phone permission is
   expected.
9. The privacy-check script SHALL be extended (task 2): WatchConnectivity only in the two named adapter
   folders; HealthKit and WatchKit workout/haptic APIs only in `WhooshWatch/Services/` (and the one phone
   file that calls `startWatchApp`); the package and `Models`/`Metrics` import Foundation only;
   `WhooshWatch/` imports no CoreLocation, MapKit, AVFoundation, Photos, or networking.
10. Wire logs SHALL contain no payload content beyond ids, types, and outcome codes, and SHALL NOT be
    written to a shared container or uploaded.

## Requirement 20: Resilience and degradation

**Priority:** Important

**User story:** As a rider, I want things to degrade calmly and visibly.

### Acceptance Criteria

1. IF the watch is not installed, not paired, not reachable, not authorized, in the wrong mode (Theater,
   Water Lock, Do Not Disturb), or low on battery THEN the ride continues, the phone channels carry the
   alerts, and the readiness screen and watch explain the state.
2. IF the keep-alive session is lost or refused THEN the watch reports it, the fan-out stops treating the
   watch as haptics-ready, and the rider hears about it.
3. IF the watch app is updated mid-ride or the versions differ THEN the negotiated common version applies;
   if there is no common version the rider is told calmly and phone channels carry alerts.
4. IF a WatchConnectivity call errors THEN the typed failure is surfaced; there are no unbounded retries and
   no unbounded queues (outstanding user-info transfers are capped and stale ones cancelled).
5. IF the watch is low on battery (≤ 15%) THEN the watch reports it and the phone announces it once; at
   ≤ 5% the watch ends the keep-alive session early to preserve itself and says so.
6. IF the rider's phone and watch are both on a ride and the watch clock and phone clock differ THEN no
   behavior depends on their agreement (Requirement 8.2).
7. Errors shown to the rider SHALL be actionable or dismissible and SHALL NOT expose raw framework text.
8. A tie between a phone-UI action and a watch command SHALL resolve by the state guards, never by
   arrival-time heuristics.

## Requirement 21: Testing, demo-mode coordination, and QA

**Priority:** Important

**User story:** As the team, I want to exercise haptics, commands, and the crash countdown without riding.

### Acceptance Criteria

1. All pure logic SHALL be **test-first** with Swift Testing: the codec and version negotiation, the
   allowlist, the command reducer and dedupe cache, start arming, freshness, haptic selection and limiting,
   the link and workout state machines, the transport policy, the readiness evaluator, the routing /
   escalation additions, the elapsed-time projector, and the crash-countdown model.
2. The link SHALL be tested with `FakeWireLink` and `LoopbackWireLinkPair` (delay, drop, duplicate,
   reorder, unreachable windows); `HKWorkoutSession`, `WKInterfaceDevice`, and notifications SHALL be
   behind fakes.
3. Real WatchConnectivity, workout-session, background, haptic, battery, and latency behavior SHALL be
   verified manually on the owner's watch and the iPhone 14 and logged in `manual-qa.md` (created by
   task 28), with results recorded in the design's "Measured results".
4. The **feasibility spike** (task 1) SHALL run before any production watch code, reusing
   `spikes/watch-haptics/` unmodified first; extra tests go in a new spike folder, not by editing it.
5. **Demo-mode coordination** (the demo-mode spec, referenced by name only): demo mode's forced
   rear-vehicle alert and crash drill SHALL reach the wrist through the same fan-out, labeled DEMO, with
   no new demo-only path; the "Feel the patterns" preview and the haptics test SHALL work without demo mode.
6. The wire contract SHALL have **golden fixtures** (encoded envelopes) checked into the package tests so
   a change to the wire format is a visible diff.
7. Every state-machine row in the design SHALL be a unit test (link, remote reducer, arming, workout
   session, countdown model).
8. Performance targets (Requirement 22) SHALL be measured, not assumed.
9. Tasks that touch real framework behavior SHALL name their device check; a task is not done until it is
   logged.

## Requirement 22: Latency, battery, and performance budgets

**Priority:** Important

**User story:** As the team, I want honest numbers for how fast and how costly the watch is.

### Acceptance Criteria

1. The design SHALL list latency and battery **budgets as hypotheses (verify)** with a measurement
   protocol, and the measured numbers SHALL be recorded in "Measured results" before any copy or pitch
   quotes them. Quote conditions and sample size, or not at all (the spike's rule).
2. Starting hypotheses: link round trip p50 ≤ 0.5 s and p95 ≤ 1.5 s while reachable; alert-to-wrist p95 ≤
   1.5 s; command-to-visible-confirmation p95 ≤ 2 s; crash-cancel-to-confirmation p95 ≤ 2 s; first haptic
   after `startWatchApp` documented as measured (forum reports of a 30–60 s delay in 2017 are **(verify)**).
3. Watch battery cost of the keep-alive session plus the link SHALL be measured over 60 minutes with the
   spike's T8 method (baseline session only; plus heartbeat; plus a haptic burst), and the watch battery
   SHALL be shown to the rider before a ride.
4. The main thread on both devices SHALL stay responsive; WatchConnectivity work SHALL not block the
   phone's ride loop; the ride's metric updates SHALL not degrade with the watch attached.
5. The link SHALL NOT generate more than the heartbeat rate plus events; the slow path (display off) SHALL
   use the context channel.
6. The phone's audio / camera / GPS budgets (rear-camera Req 12) SHALL be re-measured once with the watch
   attached to confirm it adds no meaningful cost.

## Requirement 23: Future seams and out-of-scope devices

**Priority:** Future-seam

**User story:** As the team, I want v1 not to paint us into a corner.

### Acceptance Criteria

1. **Out of scope, with no tasks:** the owner's Garmin fenix 6x (a different SDK and language, a separate
   app) and Whoop (no documented way for an app to trigger it: vibration proposal) are not supported by
   this spec.
2. An **external Bluetooth haptic device** (vibration proposal option D) SHALL be supportable later as
   another `AlertSink` channel without changing the wire contract or the fan-out; its Bluetooth permission
   and background-mode needs are decided then (the vibration proposal notes the `bluetooth-central` mode
   and usage string).
3. A **mirrored workout** data channel (`startMirroringToCompanionDevice` /
   `sendToRemoteWorkoutSession`) MAY replace or supplement WatchConnectivity behind `WireLink` if the spike
   shows WatchConnectivity is not reliable enough (open decision O-W10).
4. A **standalone** watch ride, a watch-native detector, double-tap Cancel on watches that support it, and
   directional haptic hints from the detector's position hint are future ideas and SHALL NOT be built here.
5. Newer-watchOS features SHALL be adopted only behind availability checks.

---

## Non-functional notes

- **Honest about the wrist.** A watch may be on a locked screen, a muted mode, or low on battery. Whoosh
  tells the rider what it can confirm and never promises a buzz was felt; the haptics test and the
  acknowledgement make the channel's state visible.
- **Honest about iOS.** The watch cannot start a ride unless the phone app is in the foreground and armed,
  cannot relaunch a force-quit phone app, and cannot wake its display. This spec says so and designs
  around it.
- **Fallback ladder.** Watch haptics, phone audio, notification, ride-summary note. The first channel that
  works carries the alert; the summary records the rest.
- **Spike first.** The design's central bet (a cycling workout session keeps the app reachable and
  haptic-capable with the wrist down) is documented by Apple but unmeasured on the owner's watch.

## Traceability

Every acceptance criterion maps to tasks in `tasks.md` via `_Requirements:_` annotations, and
`design.md` references requirement numbers where it explains how each is satisfied.
