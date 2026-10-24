# Requirements — Whoosh Rear-Mounted Camera Recording

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O-CAM1–O-CAM6 (`design.md`, "Owner resolution"). No code may be written until the iOS
owner approves `requirements.md`, `design.md`, and `tasks.md`. This spec contains **no Swift
code** by design.

## Introduction

Whoosh is an iOS cycling-safety app. This spec adds **rear-mounted camera recording**: the
rider clips the phone onto a holder on the back of the seat (seat post or rack) with the phone's
back camera facing rearward, and Whoosh records the road behind the bike while GPS tracks the
ride. The recording works **now**, without the vision model; Teammate B's `HazardDetector` later
subscribes to the same frames through a defined seam. Role C's database later receives near-miss
**events** only, never video.

The owner context that shaped this spec (October 24, 2026): *"Someone is currently working on
the vision model (Teammate B) and someone else on the database (Role C). The idea is that the
phone clips onto a phone holder on the back of the seat to record the cars coming. I can do the
recording stuff now and still have the camera even though the model isn't implemented. It should
also record even when the phone/screen is off."*

That context **changes core assumptions** of the earlier specs (the rider can no longer see or
touch the phone while riding, and iOS does not allow a third-party camera session to run on a
locked or backgrounded iPhone). Each changed assumption is recorded explicitly in "Changed
assumptions" below and reasoned through in `design.md`.

Related specs and documents (reference, do not duplicate):

- `../ride-recording-mvp/` — the implemented ride engine, `HazardDetector`/`AlertManager` seams.
- `../crash-response/` — approved; this spec supplies the real `FootageBuffer` (its task 34) and
  adds a wrist-reachable cancel for the countdown.
- `../demo-mode/` — a parallel spec (demo toggle, simulated ride, simulated rear-vehicle
  alerts). This spec only **coordinates** with it (Requirement 18.5); it neither creates nor edits
  its files.
- A future **Apple Watch companion** spec (referenced, not written here; open decision O-CAM1).
- `../../steering/privacy.md`, `product.md`, `tech.md` (updated by this job) and
  `../../team/team-plan.md`.

## How to read this document

- Acceptance criteria use EARS-style phrasing (WHEN/WHILE/IF ... THEN ... SHALL ...) so each is
  individually verifiable.
- **Priority** per requirement: `Demo-critical` (must work live), `Important` (strongly
  expected), `Stretch` (valuable, never blocking), or `Future-seam` (defined now, built later).
- "Configurable" means the value lives in one tuning type (`RideCameraTuning`, see the design),
  not hard-coded at call sites.
- Numbers marked **(verify)** are starting hypotheses to be measured on the primary demo device
  (iPhone 14) before they are treated as promises.
- Cross-spec references say "crash-response task N" or "MVP task N".

## Glossary

- **Rear-mounted** — the phone sits on a holder on the back of the bike with its **back camera
  facing rearward**; the screen faces the rider's back and is not visible or reachable.
- **Mount & frame** — the pre-ride screen where the rider aims the camera, checks level, storage,
  battery, and a test recording **before** mounting the phone.
- **Segment** — one short (default 15 s) independently playable video file written by the
  recorder.
- **Ring buffer** — the bounded, on-device set of the most recent unpinned segments; the oldest
  is deleted first.
- **Pin / clip** — to *pin* is to keep the segments around an instant; the kept, user-visible
  result is a *clip*, attached to a ride.
- **Frame pipeline** — the seam that delivers frames (pixel buffer, timestamp, orientation) to
  zero or more consumers off the main actor.
- **Frame consumer** — a type that subscribes to the pipeline (for example Teammate B's detector).
- **Ride mode (screen-dim mode)** — the foreground, true-black, minimum-brightness, touch-locked
  presentation used while the camera records, so the phone looks off.
- **Eyes-free surface** — the in-ride control and alert channel when the phone is out of reach:
  the recommended Apple Watch (wrist haptics, controls) plus audio.
- **RideStatus / RideRemoteControl / AlertSink** — the seams the eyes-free surfaces need
  (defined here; the watch app itself is a separate spec).
- **Interruption** — iOS stopping the capture session (backgrounding, lock, call, system
  pressure, another app using the camera).

## Changed assumptions (recorded explicitly)

| ID | Earlier assumption | New assumption | Where it is superseded or reasoned |
| -- | ------------------ | -------------- | ---------------------------------- |
| A | The rider holds or can glance at the phone; the active-ride screen is the in-ride UI; hold-to-stop and Pause are touched during the ride; haptic alerts are felt through the phone. | The phone is **rear-mounted facing backward**: the rider can neither see nor touch the screen, and phone haptics on a seat post are not felt reliably. The ride is **started and the camera framed before mounting**. In-ride control and alerts move to another surface: the **recommended Apple Watch companion** (separate spec) plus audio. | Requirements 1, 9, 13; design "Rear-mount consequences" and "Eyes-free surfaces"; open decision **O-CAM1**. Crash-response countdown cross-reference: Requirement 13.7. |
| B | Recording is foreground and screen-on only (MVP 3.6, Non-functional notes); "record even when the screen is off" was not considered. | iOS does **not** let a third-party iPhone app keep an `AVCaptureSession` running while the app is backgrounded or the device is locked. The supported design is **ride mode**: the app stays in the foreground, idle timer disabled, true-black minimum-brightness touch-locked screen. If the phone is locked anyway, camera recording **stops cleanly** and GPS continues only because the `location` background mode is now enabled. | Requirements 10, 11; design "Background reality" and "Background location decision"; open decision **O-CAM2**. Resolves the MVP's foreground-only location choice and crash-response O1(b) **for GPS**. |
| C | The camera is future; `HazardDetector` has no input and `NoopDetector` never touches the camera; no camera permission in the MVP. | **Camera recording is built first, independent of the model.** A `CameraCaptureService` behind protocols feeds a **frame pipeline**; Teammate B's detector becomes a frame consumer without touching capture code. Camera permission is requested when the rider first enables rear camera recording. | Requirements 2, 3, 4, 15; design "Frame pipeline" and "HazardDetector seam update". Supersedes MVP 8.4 and the `privacy.md` "no camera permission in the MVP" rule (updated by this job). |
| D | A footage buffer is a future seam (`FootageBuffer`, crash-response task 34). | Dashcam-style **rolling segments in a bounded on-device ring buffer**; clips are **pinned** on demand (manual save, detection event, crash event). The pinning path is the real `FootageBuffer`. | Requirements 5, 6, 7, 8; design "Recording model". Delivers crash-response task 34. |
| E | Camera data is "processed on device, not uploaded" (privacy steering, future). | Footage is **stored** on device (not just processed), never uploaded automatically, never sent in crash messages; Role C receives near-miss **events** only. Other road users' faces and plates are in the footage. Optional microphone is off by default. | Requirement 16; `privacy.md` (updated); privacy-check rule changes (Requirement 16.9). |
| F | The pre-ride flow is Home → Start. | Add **Mount & frame**, a **recording indicator** (ride screen and ride mode), and **clip lists** in summary/history. | Requirements 9, 10, 18. |
| G | Team split: iOS app / vision / backend with a `HazardDetection` contract. | iOS owner: capture, recording, ring buffer, clips, ride mode, frame-pipeline seam, watch seams. Teammate B: model + a `HazardDetector` that consumes frames. Role C: near-miss events in the database (no video). New team risks: heat on a seat post in sun, vibration blur, rain, battery drain (camera + GPS + screen), storage. | `../../team/team-plan.md` (updated); design "Risks". |

---

## Requirement 1: Scope, positioning, and the rear-mount ride flow

**Priority:** Demo-critical

**User story:** As a cyclist, I want my phone to record the road behind me from a seat-mounted
holder, and I want the app to work without my touching it while I ride.

### Acceptance Criteria

1. The system SHALL record video from the phone's **back camera** to on-device storage while a
   ride is active, when the rider has enabled "Record rear camera" (off by default).
2. The documented ride flow SHALL be: enable rear camera → **Mount & frame** → start the ride on
   the phone → (after a short mount grace period) the phone enters **ride mode** → the rider
   mounts the phone and rides → ride controls and alerts use the eyes-free surface (Requirement
   13) → the ride is ended with a deliberate action (watch hold, or unlock the phone and hold
   Stop).
3. WHEN rear camera recording is off or unavailable THEN every MVP flow SHALL behave exactly as
   before (record, summary, history, settings). The camera is additive.
4. A camera, writer, storage, thermal, or permission failure SHALL NEVER stop, pause, or corrupt
   GPS ride recording (Never block a ride).
5. The system SHALL NOT claim that recording will capture any particular incident, that footage is
   legal evidence, or that detection prevents or predicts collisions. Copy says recording is for
   the rider's own records and that detection is experimental.
6. The rear-camera feature SHALL be usable and demoable **without** the vision model: with the
   no-op detector it records, saves manual clips, and shows them.
7. The system SHALL be designed so that every framework touchpoint (AVFoundation, Photos,
   WatchConnectivity, UIKit screen control) sits behind a protocol with a fake, per the
   existing layering table.

## Requirement 2: Camera and microphone permissions

**Priority:** Demo-critical

**User story:** As a cyclist, I want Whoosh to ask for the camera only when I turn recording on,
and to keep working if I decline.

### Acceptance Criteria

1. The system SHALL NOT request camera authorization at launch, on Home, or when a ride starts
   without the feature enabled. WHEN the rider first enables "Record rear camera" THEN the system
   SHALL show an in-app explanation (what is recorded, that it stays on the device, that other
   people may appear in it) and only then trigger the system prompt.
2. The camera permission state SHALL be an explicit enum (`notDetermined`, `authorized`,
   `denied`, `restricted`) mirrored in the UI.
3. IF permission is denied or restricted THEN the toggle SHALL show the state with icon + text
   and an "Open Settings" path; rides and history SHALL be unaffected; the app SHALL NOT crash,
   hang, or dead-end.
4. IF permission is revoked while a ride is active THEN the system SHALL stop the camera cleanly
   (finalize the current segment), notify the rider through the eyes-free surface (Requirement
   13), and continue the ride.
5. The system SHALL NOT request microphone authorization unless the rider enables optional audio
   recording (Requirement 14).
6. The system SHALL request Photos **add-only** access only when the rider explicitly exports a
   clip (Requirement 8.8), and notification authorization only as described in Requirement 11.6.
7. The `NSCameraUsageDescription` string SHALL be updated from the "experimentally detect
   approaching vehicles" wording to a purpose-specific recording statement (see `privacy.md`).

## Requirement 3: Camera capture service

**Priority:** Demo-critical

**User story:** As the app, I want a reliable, power-aware capture session so recording keeps
working for a whole ride.

### Acceptance Criteria

1. The `CameraCaptureService` (AVFoundation, `Services/Camera/` only) SHALL capture from the
   **back wide-angle camera** by default, behind a `CameraCapturing` protocol with a fake.
2. The system SHALL provide configurable **capture profiles** (resolution, frame rate, codec,
   bitrate): Standard 1080p/30, Efficient 720p/30, and Reduced 720p/lower frame rate (values in
   the design); HEVC when supported, H.264 otherwise. A profile that the device format list cannot
   satisfy SHALL fall back to the nearest supported one, never fail the ride.
3. The service SHALL enable video stabilization when supported.
4. The recording orientation SHALL be locked to the **mount orientation** chosen in Mount & frame
   and written into the video's transform so playback is upright; rotating the phone SHALL NOT
   change an active recording.
5. The service SHALL handle low light and motion blur by bounding the maximum exposure duration
   and allowing the system to raise sensitivity, and SHALL prefer far-range continuous autofocus
   suited to a road scene; a dark scene SHALL be surfaced as a hint, never as a blocker.
6. The service SHALL be **thermal-state aware** (Requirement 12) and SHALL observe session
   interruptions and runtime errors, mapping them to the recording state machine (Requirement 5.9).
7. All session, device, and sample-buffer work SHALL run **off the main actor**; start and stop
   SHALL NOT block the UI.
8. WHEN the ride ends or the feature is turned off THEN the session SHALL be fully torn down (no
   leaked session; the system camera indicator turns off).
9. Capture logic that is pure (profile selection, format choice, level math) SHALL be
   unit-tested without a camera.

## Requirement 4: Frame pipeline and consumer seam (for Teammate B)

**Priority:** Demo-critical (it unblocks the detector)

**User story:** As the vision teammate, I want to receive camera frames through a stable seam
without touching capture or recording code.

### Acceptance Criteria

1. The system SHALL define a `FrameConsumer` protocol and a `FramePipeline` that delivers each
   `VideoFrame` — pixel buffer, presentation timestamp, wall-clock capture time, display
   orientation, sequence number, and a discontinuity flag — to **zero or more** registered
   consumers.
2. WHILE no consumer is registered THE pipeline SHALL do no per-frame work beyond a registry
   check (no copies, no conversions).
3. Consumers SHALL be invoked **off the main actor**, each with its own serial execution, and
   SHALL declare their needs (maximum frames per second, preferred pixel format, maximum
   dimension hint).
4. **Backpressure rule:** each consumer has a single-slot, latest-wins mailbox. IF a consumer is
   still processing, THEN a newer frame SHALL replace any pending frame (the replaced frame counts
   as dropped); the pipeline SHALL NEVER wait on a consumer, and capture and the segment writer
   SHALL NEVER be delayed by a consumer.
5. Per-consumer rate limiting SHALL drop frames above the consumer's declared maximum frames per
   second using a pure, unit-tested policy; delivered, rate-dropped, and busy-dropped counts SHALL
   be exposed for diagnostics.
6. A consumer SHALL NOT retain more than one frame beyond its processing call; the pipeline SHALL
   retain at most one pending frame per consumer so the capture buffer pool cannot be exhausted.
   Consumers needing history SHALL copy.
7. Consumers SHALL be registrable and removable **while recording** without interrupting
   recording. A consumer that is slow, throws, or crashes its own work SHALL NOT affect other
   consumers or recording.
8. After an interruption or a capture-format change the next frame SHALL carry the discontinuity
   flag so a detector can reset temporal state.
9. The `HazardDetector` contract SHALL be updated (design "HazardDetector seam update"): a
   camera-based detector obtains frames **only** by being a frame consumer; it never creates or
   owns a capture session. The `HazardDetection` value type is unchanged (frozen contract).
10. The pipeline SHALL be testable with a `FakeCameraSource` that emits synthetic frames on
    command, and (stretch) a `FileFrameSource` that replays a recorded clip through the same
    seam so a detector can be exercised on real footage without riding.

## Requirement 5: Rolling segment recording and the ring buffer

**Priority:** Demo-critical

**User story:** As a cyclist, I want the app to keep the last few minutes of video without ever
filling my phone.

### Acceptance Criteria

1. WHILE the camera is recording THE system SHALL write **segments** of a configurable length
   (default 15 s, range 10–30 s) as independently playable MP4 files via `AVAssetWriter`, HEVC
   when supported.
2. A new segment SHALL begin on the frame following the end of the previous one, with no gap larger
   than one frame interval under normal operation; writer rotation SHALL NOT block capture.
3. Each segment SHALL be written with movie fragments so that if the app is killed mid-segment at
   most one fragment interval is lost and the file remains playable **(verify)**.
4. The ring buffer SHALL be bounded by **both** a maximum duration (default 10 min) and a maximum
   byte size (default 1 GB); WHEN either bound is exceeded THEN the **oldest unpinned** segments
   SHALL be deleted first.
5. Eviction SHALL be a pure function and SHALL NEVER delete: the segment currently being written,
   a pinned segment, or a segment inside a pending post-roll window.
6. IF the writer is not ready for more data THEN the frame SHALL be dropped and counted; the
   system SHALL NOT block or buffer unboundedly.
7. WHEN a ride ends THEN unpinned segments SHALL be deleted after any in-flight pin completes
   (privacy default: nothing is kept that the rider did not save). On launch, orphaned segments
   from an earlier run SHALL be purged.
8. Segment files SHALL be excluded from device backups and use a file-protection class that allows
   writing while the device is locked after first unlock **(verify)**.
9. The camera recording lifecycle SHALL be an explicit state machine (`off`, `preparing`,
   `recording`, `degraded`, `interrupted`, `stopping`, `failed`) with the transitions in the
   design; undefined transitions SHALL be no-ops. Its reducer SHALL be pure and unit-tested.
10. The system SHALL record, per segment, start/end time, byte size, profile, and whether audio is
    present, in a segment index used by the ring buffer and pinning.

## Requirement 6: Saving clips (pinning)

**Priority:** Demo-critical (manual); Important (detection); Stretch (post-ride save)

**User story:** As a cyclist, I want to save the moment around something that just happened
without stopping the ride or touching the phone.

### Acceptance Criteria

1. The system SHALL support three pin sources: **manual** (a "Save clip" action on the phone or the
   eyes-free surface), a **detection event** (a `HazardDetection` that passes the near-miss
   policy), and a **crash event** (Requirement 7).
2. Each source SHALL have a configurable pre-roll and post-roll (defaults: manual 30 s / 15 s,
   detection 15 s / 10 s, crash 60 s / 30 s). The pin window SHALL be computed by a pure function
   that snaps to segment boundaries, clamps to what exists, and keeps precise in/out offsets.
3. Pinning SHALL NOT interrupt recording. Pinned segments SHALL be moved or linked out of the ring
   so ring eviction cannot delete them.
4. Overlapping or near-adjacent windows (within a configurable gap) SHALL **coalesce** into one
   clip with the union range, up to a maximum clip duration (default 180 s); every contributing
   reason SHALL be kept on the clip.
5. WHILE a post-roll is pending THE covering segments SHALL be protected from eviction. IF the
   ride ends or the camera stops before the post-roll completes THEN the clip SHALL be finalized
   with what exists and flagged "ended early".
6. Auto-pins (detection) SHALL be rate-limited by a cooldown (default 20 s), a per-ride cap
   (default 10), and the pinned-storage cap; manual saves SHALL be debounced (default 2 s) and
   allowed until the pinned-storage cap is reached.
7. WHEN a clip is saved or cannot be saved THEN the rider SHALL get feedback on the eyes-free
   surface (haptic, short audio cue) and a tiny confirmation in ride mode; IF the camera is not
   recording THEN the system SHALL say "nothing to save" rather than silently doing nothing.
8. Each clip SHALL store: id, ride id, reasons, start/end time, in/out offsets, duration, byte
   size, thumbnail, audio flag, state (`pending`, `saved`, `endedEarly`), and (for detection or
   crash) a reference to the event.
9. Pinning logic (windows, coalescing, caps, cooldowns) SHALL be pure and unit-tested.

## Requirement 7: Crash footage — the real `FootageBuffer`

**Priority:** Stretch (crash-response is post-MVP and opt-in)

**User story:** As a rider, I want footage from just before a probable crash kept safely on my
phone, and never sent to anyone.

### Acceptance Criteria

1. The system SHALL provide a `FootageBuffer` implementation (for crash-response's protocol) that
   pins a crash window (default 60 s pre / 30 s post) through the same pinning path, with
   reason `crash`.
2. `preserve` SHALL return a local clip reference **immediately** (the post-roll may still be
   pending) and SHALL NEVER block the crash countdown. IF the camera is not recording THEN it
   SHALL return none ("no footage" is a normal outcome, not an error).
3. Footage SHALL NEVER be uploaded, attached to a message, or linked by URL. The crash notifier
   request type has no footage field (crash-response NOFOOT test); no camera-service type SHALL be
   reachable from `Services/Notification` or `Services/Sync` (privacy-check rule, Requirement
   16.9).
4. Deleting a crash record's footage from the crash alert log SHALL delete the clip (files,
   thumbnail, record).
5. The crash-event clip SHALL appear in the ride's clip list labeled with icon + text.

## Requirement 8: Clip management — attach, view, delete, export

**Priority:** Demo-critical (list, play, delete); Important (export, retention)

**User story:** As a cyclist, I want to find, watch, and delete my clips, and export one only
when I choose.

### Acceptance Criteria

1. Clips SHALL be attached to the ride they were recorded in and listed in the ride **summary**
   (also used as history detail) with thumbnail, time into the ride, duration, and reason (icon +
   text: "Saved by you", "Vehicle detected (experimental)", "Crash").
2. History rows SHALL show a clip count with icon + text when a ride has clips.
3. WHEN the rider selects a clip THEN the system SHALL play it with standard transport controls
   within the app.
4. The rider SHALL be able to delete a single clip (with confirmation), all clips of a ride, and
   all clips from Settings. Deletion SHALL remove the files, thumbnail, and record (real deletion).
5. Deleting a ride (swipe in History, or "Delete all rides") SHALL delete its clips.
6. Clips SHALL be stored locally only, excluded from backups, and SHALL NOT be uploaded by any
   code path.
7. Settings SHALL show clip storage used and the pinned-storage cap; clips SHALL expire after a
   configurable retention (default 30 days, open decision O-CAM4) with an "expires in N days"
   indication; a rider-initiated "Keep" MAY exempt a clip (Stretch).
8. **Export** to Photos SHALL occur only on an explicit rider action per clip, SHALL copy (never
   move) the clip, and SHALL request add-only Photos access at that moment. The export code SHALL
   live in its own file.
9. Metadata (`ClipRepository`) SHALL be behind a protocol with SwiftData and in-memory
   implementations; the segment files SHALL be behind a separate store protocol with a fake.

## Requirement 9: Mount & frame (pre-ride)

**Priority:** Demo-critical

**User story:** As a cyclist, I want to aim and check the camera before I mount the phone so
the footage is actually useful.

### Acceptance Criteria

1. Mount & frame SHALL show a **live preview**, a **level indicator** (roll and pitch relative to
   the chosen mount orientation, computed by a pure function), and a framing guide.
2. It SHALL offer a **test recording** (default 10 s) followed by playback, confirming that a file
   was written, its size, and the measured bitrate.
3. It SHALL show a **readiness checklist** with icon + text rows: storage free (Requirement 12),
   battery level and charging, Low Power Mode, thermal state, camera permission, location
   permission, lens-clean reminder, secure-mount reminder, and a Focus/Do Not Disturb reminder.
   A failing row SHALL explain the consequence and SHALL NOT hard-block the ride unless recording
   cannot work (no permission, no space).
4. It SHALL let the rider choose profile (Standard/Efficient), mount orientation (auto-detected
   from gravity, confirmable), and whether to use ride mode.
5. WHEN the rider starts the ride THEN the system SHALL show a **mount grace countdown** (default
   20 s) with "Dim now" and "Keep screen on", after which ride mode begins.
6. Mount & frame SHALL be reachable from Home (rear camera card) and from the Start Ride path
   when rear camera recording is enabled; it SHALL be skippable ("Start without framing") after
   the first successful framing, and SHALL never request permissions other than the camera.
7. Preview and test-recording SHALL be torn down on exit; the preview SHALL work with the fake
   camera in previews and tests.

## Requirement 10: Ride mode (screen-dim mode)

**Priority:** Demo-critical

**User story:** As a cyclist, I want the phone to look and behave as if it were off while the
camera and GPS keep running.

### Acceptance Criteria

1. WHILE a ride is active AND rear camera recording is on AND ride mode is on THE app SHALL stay
   in the foreground with the **idle timer disabled** and SHALL present a **true-black** screen
   with minimal content.
2. The system SHALL lower screen brightness to the minimum on entering ride mode, SHALL remember
   the rider's original brightness, and SHALL restore it on exit, on ride end, when the app resigns
   active, and (via a persisted guard) on the next launch if a previous run ended while dimmed.
3. The screen SHALL **lock touch input** (rain and bumps). WHEN the rider performs a deliberate
   **two-finger long press** (default 1 s) THEN the system SHALL unlock for a configurable window
   (default 10 s of inactivity), restoring brightness and showing the controls (including Hold to
   Stop), then re-dim and re-lock.
4. The ride-mode screen SHALL show a **tiny red recording dot** (never hidden while recording) and
   nothing else except transient confirmations ("Clip saved") and, when relevant, an amber state
   dot for camera/GPS trouble. The dot SHALL shift position slowly to protect the display.
   System camera and location indicators SHALL NOT be hidden or imitated.
5. Ride mode SHALL be a pure, unit-tested state machine (`normal`, `dimLocked`, `unlockedTemporarily`,
   `suspended`) with the transitions in the design, including: crash countdown start forces
   full brightness and unlock; app resigning active suspends it.
6. VoiceOver users SHALL have an accessible unlock path (a custom action on the ride-mode element)
   and a spoken description ("Ride mode. Camera recording."); the gesture SHALL NOT be the only way.
7. IF the rider leaves ride mode by ending the ride THEN brightness and idle timer SHALL be
   restored before the summary appears.
8. Ride mode SHALL be optional (Settings, default on when the camera records); with it off the app
   uses the existing active-ride screen.

## Requirement 11: Locked, backgrounded, or interrupted phone; background location

**Priority:** Important

**User story:** As a cyclist, I want the app to behave honestly if my phone locks or another app
takes over, and I want my route kept.

### Acceptance Criteria

1. The system SHALL NOT rely on the multitasking camera access entitlement or any other mechanism
   to keep a camera session alive while backgrounded or locked (see design: verified findings).
2. WHEN the capture session is interrupted (backgrounded, locked, call, system pressure, camera in
   use elsewhere) THEN the system SHALL finalize the current segment cleanly (using a short
   background task), enter `interrupted` with the reason, and record the gap.
3. WHEN the interruption ends AND a ride is active THEN the system SHALL resume recording in a new
   segment automatically (bounded retries), with the discontinuity flag set for consumers.
4. WHEN the camera is interrupted for longer than a short threshold (default 5 s) THEN the system
   SHALL tell the rider through the eyes-free surface and, when the phone is locked, a local
   notification ("Camera paused — Whoosh can't record while the phone is locked. Open Whoosh to
   resume."). It SHALL NOT claim recording continued.
5. **GPS in the background (recommended, open decision O-CAM2):** the app SHALL declare the
   `location` background mode and, only while a ride is active, enable background location updates
   with the background-location indicator, using **When-In-Use** authorization (no Always
   prompt) **(verify on device)**. WHEN the phone locks THEN the ride's GPS SHALL continue and
   incoming points SHALL be appended as usual.
6. Notification authorization for "camera paused" notices SHALL be requested lazily with an
   in-app explanation, only after rear camera recording has been enabled; denial SHALL only reduce
   the notice channel.
7. Pin windows spanning a gap SHALL include only existing segments and flag the clip as having a
   gap.
8. The MVP's persistence safeguards (periodic snapshot, recovery) SHALL continue to apply.

## Requirement 12: Thermal, battery, and storage budgets

**Priority:** Important (policy functions Demo-critical for storage guard)

**User story:** As a cyclist, I want recording to degrade gracefully instead of overheating my
phone, draining it, or filling it.

### Acceptance Criteria

1. The **thermal policy** (pure, unit-tested) SHALL map thermal state and capture-session system
   pressure to a profile step: `nominal`/`fair` → requested profile; `serious` → reduce frame
   rate first, then resolution at the next segment boundary; `critical` → stop camera recording
   (finalize) while GPS continues. Step-ups SHALL use hysteresis (default: at least 5 minutes at
   `fair` or better, at most one step-up per 10 minutes) to avoid flapping.
2. The **storage guard** (pure) SHALL use the free space available for important usage: refuse to
   start the camera below a start minimum (default 2 GB) with a plain message; warn below a warn
   level (default 1 GB); stop camera recording below a stop floor (default 500 MB) while GPS
   continues; and shrink the effective ring cap before the floor is reached.
3. The **battery policy** (pure) SHALL suggest the Efficient profile at or below 20% when not
   charging, and stop the camera at or below a floor (default 8%) so GPS can complete the ride;
   Low Power Mode SHALL default the profile to Efficient.
4. Every degradation SHALL be announced on the eyes-free surface and visible in ride mode (amber
   dot) and the summary ("Recording reduced at 24:10 — phone warm"); none SHALL be silent.
5. The design SHALL list storage, battery, and thermal **budgets with numbers to verify on the
   iPhone 14**, and a measurement protocol, and the numbers SHALL be recorded in the design's
   "Measured results" after device runs.
6. A longer-than-expected ride SHALL NOT grow storage unboundedly: the ring is bounded and clips
   are capped.

## Requirement 13: Eyes-free control and alert surfaces (seams)

**Priority:** Important (seams and fakes); Future-seam (watch implementation)

**User story:** As a cyclist with a rear-mounted phone, I want to control the ride and feel
warnings without reaching the phone.

### Acceptance Criteria

1. The system SHALL define a **`RideStatus`** snapshot (ride state, active-duration anchor,
   distance, speed, camera state, storage/thermal/battery flags, banner, optional crash countdown
   deadline, last clip time) and a **`RideRemoteControl`** protocol that publishes it and receives
   typed commands, with Noop and Fake implementations. WatchConnectivity SHALL be confined to
   `Services/Remote/` and implemented only by the watch spec.
2. Remote commands SHALL be: pause, resume, save clip, stop (only with a "confirmed by deliberate
   hold" flag), and cancel crash countdown. Start is **not** a remote command in v1 (the ride is
   started and framed on the phone). The ride engine's existing public intents SHALL be reused;
   the engine SHALL NOT be modified.
3. The system SHALL define an **`AlertSink`** protocol (one output channel: watch haptic, phone
   speaker/headphone audio, phone haptic, local notification) and a **fan-out `AlertManager`**
   implementation that routes each `AlertKind` to the available sinks via a pure, unit-tested
   `AlertRoutingPolicy`. The existing `AlertManager` protocol SHALL be unchanged.
4. `AlertKind` SHALL grow additively (rear-vehicle caution exists; new: camera interrupted,
   camera resumed, camera stopped with reason, clip saved, clip not saved, phone battery low).
5. Alerts SHALL remain non-blocking and on-device; audio SHALL use a session category that mixes
   with other audio and does not stop music; the fan-out SHALL never delay recording.
6. The recommended in-ride surface is an **Apple Watch companion** (start excluded; pause/resume,
   save clip, stop, live time/distance, camera health, wrist haptics for rear-vehicle caution,
   camera/storage problems, and the crash countdown) — **open decision O-CAM1**, specified as a
   separate follow-up spec.
7. **Crash-response cross-reference:** the countdown UX assumes the rider can tap the phone. With a
   rear mount, WHEN a crash countdown starts THEN ride mode SHALL exit to full brightness and
   unlocked touch, the phone SHALL speak and sound the countdown, `RideStatus` SHALL carry the
   countdown deadline, and the watch (when present) SHALL be able to send **cancel crash
   countdown**. Without a watch the audible phone countdown and the on-screen cancel remain the
   only cancel paths; consent copy SHALL say so. (Short note recorded in `crash-response/design.md`
   "Risks"; that spec is otherwise unchanged.)
8. Without a watch the system SHALL still work: audio cues through the phone speaker or headphones,
   unlock gesture for on-phone control. Informational note: some places restrict headphone use
   while cycling.

## Requirement 14: Optional audio recording

**Priority:** Stretch

### Acceptance Criteria

1. Audio recording SHALL be **off by default**. WHEN the rider enables it THEN the system SHALL
   explain that conversations and ambient sound may be recorded, request microphone authorization,
   and record audio into segments.
2. IF microphone permission is denied THEN video recording SHALL continue without audio.
3. Clips with audio SHALL be labeled; the microphone usage string SHALL be purpose-specific.
4. Informational: laws on recording audio vary by place; in-app guidance SHALL say so without
   giving legal advice.

## Requirement 15: Detection events and near-miss records

**Priority:** Important (local); Future-seam (sync)

**User story:** As a cyclist, I want vehicle detections to save a short clip and be recorded on
the ride, and as the team I want only the event, not the video, in the database.

### Acceptance Criteria

1. WHEN a `HazardDetection` arrives (on the main actor via `HazardDetector.onDetection`) THEN a pure
   `NearMissPolicy` (confidence threshold, cooldown, per-ride cap, all in tuning) SHALL decide
   whether it becomes a **near-miss event** and whether to pin a clip. Thresholds start from
   Teammate B's measured numbers; until then detection pinning is off.
2. A near-miss event SHALL be stored locally with the ride: id, ride id, time, nearest accepted
   route coordinate, kind, confidence, position hint, and an optional **local** clip id.
3. Any future upload (Role C `near_misses`) SHALL contain only the contract fields — **no clip id,
   no video, no thumbnail, no frame**. The mapping function SHALL be unit-tested for this.
4. The `HazardDetection` shape SHALL NOT change in this spec (frozen contract; changes need a
   3-way OK).
5. The detection path SHALL be exercisable by `FakeHazardDetector` and by the demo-mode simulated
   detector (Requirement 18.5) through the same seam.

## Requirement 16: Privacy, permissions, and honest copy

**Priority:** Demo-critical

**User story:** As a cyclist, and as someone riding or walking near a cyclist, I want footage to
stay private and under the rider's control.

### Acceptance Criteria

1. Footage SHALL stay on the device. No code path SHALL upload or share it automatically; export
   is only by explicit per-clip rider action (Requirement 8.8).
2. The first-enable explanation, Settings, and the clip list SHALL tell the rider: other people
   (faces, license plates) can appear in the footage; clips are stored only on this phone; short
   retention and easy deletion are provided; local laws on recording in public vary (informational
   only, no legal advice).
3. Crash messages SHALL never include footage or a footage link (crash-response requirement 7.7).
4. Role C's database SHALL receive near-miss events only (Requirement 15.3).
5. Ride sync (Settings copy) SHALL continue to state that camera video is never uploaded.
6. Copy SHALL say recording is for the rider's own records, SHALL NOT claim legal evidence or
   guaranteed capture, and SHALL frame detection as experimental. Ride mode SHALL NOT be
   described as hiding the camera; the system indicators remain and the red dot is always shown.
7. The microphone, Photos, and notification permissions SHALL each be requested only at the moment
   the related feature is used and have purpose-specific strings.
8. The `privacy.md` steering SHALL be updated (done in this job): camera now requested when the
   rider enables rear camera recording; footage local-only; microphone optional; Photos add-only;
   the "silent degradation" rule becomes "visible, calm degradation".
9. `scripts/privacy-check.sh` SHALL be updated by a task: capture and writer APIs
   (`AVCaptureSession`, `AVCaptureDevice`, `AVCaptureVideoDataOutput`, `AVCaptureAudioDataOutput`,
   `AVAssetWriter`, camera authorization) only in `Services/Camera/`; Photos APIs only in
   `Services/Camera/PhotosClipExporter.swift`; WatchConnectivity only in `Services/Remote/`; screen
   brightness and idle-timer APIs only in `Services/Screen/`; Core Motion also allowed in
   `Services/Camera/` (mount level); network-layer folders (`Services/Sync`,
   `Services/Notification`) SHALL NOT reference camera, clip, or footage types; the old allowance
   for capture APIs in `Services/Detection` is removed (detectors consume frames).
10. Footage and thumbnails SHALL NOT be written to logs, analytics, crash reports, or shared
    containers.

## Requirement 17: Resilience and degradation

**Priority:** Important

### Acceptance Criteria

1. IF the camera is unavailable, denied, interrupted, over-heated, or out of space THEN the ride
   continues; the rider is told through the eyes-free surface and the ride-mode amber dot; the
   summary notes the gap. Camera trouble SHALL NEVER be silent (the rider cannot see the screen).
2. IF the writer fails (disk error, finalize failure) THEN the system SHALL discard the bad
   segment, attempt one restart after a short delay, and otherwise enter `failed` and notify.
3. IF the app is killed during a ride THEN the next launch SHALL purge orphan segments, keep
   already-pinned clips, and the MVP interrupted-ride recovery SHALL still work.
4. IF a consumer, remote, or alert sink fails THEN recording and GPS SHALL be unaffected.
5. IF the free-space guard trips mid-ride THEN auto-pins stop first, then the camera, then (never)
   GPS.
6. Errors surfaced to the user SHALL be actionable or dismissible and SHALL NOT expose raw
   framework text.

## Requirement 18: Settings, Home, ride screen, and demo-mode coordination

**Priority:** Important

### Acceptance Criteria

1. Settings SHALL gain a "Rear camera" section: "Record rear camera" toggle (off by default;
   permission explained on enable), Quality (Standard / Efficient), Ride mode (on/off), Buffer
   length, clip storage used, retention, "Delete all clips" (destructive, confirmed), and (Stretch)
   audio. Existing rows are unchanged.
2. Home SHALL replace the inert rear-detection placeholder's *recording* implication with a "Rear
   camera recording" entry to Mount & frame; the "Rear vehicle detection — Experimental, coming
   soon" card stays as-is until a real detector exists.
3. The active-ride screen (non-ride-mode) SHALL show a recording chip (icon + text: "Recording
   video") beside the existing chips, a "Save clip" control, and camera-trouble banners; it SHALL
   still show at most three numbers.
4. Camera state changes SHALL be announced to VoiceOver on the active-ride screen.
5. **Demo-mode coordination** (`../demo-mode/`, parallel job): capture and recording are
   independent of demo mode. A simulated `HazardDetection` delivered through the `HazardDetector`
   seam SHALL flow through the same near-miss policy and pinning path so a demo can show saved
   clips; clips created that way SHALL be labeled as demo; demo mode SHALL be able to run the
   pipeline from `FakeCameraSource`/`FileFrameSource` without a bike. The exact toggle and simulated
   ride live in the demo-mode spec; any mismatch is resolved at owner review.

## Requirement 19: Accessibility, testability, and performance

**Priority:** Important

### Acceptance Criteria

1. All new controls SHALL have accessibility labels; state SHALL be icon + text, never color
   alone; primary in-app controls SHALL meet the 60 pt touch-target rule; Dynamic Type SHALL not
   truncate primary controls.
2. All pure policies and state machines (Requirements 5.5, 5.9, 6.2–6.9, 4.5, 9.1, 10.5, 12.1–12.3,
   13.3, 15.1) SHALL be unit-tested, test-first, with a controllable `Clock` and no AVFoundation.
3. Real capture, writer, thermal, brightness, background, and watch behavior SHALL be verified
   manually on device and logged in `manual-qa.md` (created by a task).
4. The main thread SHALL stay responsive while recording: no sample-buffer, writer, or file work on
   the main actor; recording SHALL NOT degrade active-ride metric updates.
5. Performance targets **(verify)** on iPhone 14: dropped-frame rate at the writer under 1% in a
   10-minute nominal-thermal run; CPU and thermal data captured per the measurement protocol;
   `FramePipeline` overhead with no consumers negligible.

---

## Non-functional notes

- **Honesty about heat, rain, and vibration:** a black phone on a seat post in direct sun may
  throttle or stop recording; rain and lens droplets degrade footage; vibration causes blur. The
  app reduces, reports, and never promises.
- **Water resistance:** iPhone water resistance is not a recommendation to ride in rain with an
  exposed phone; Whoosh makes no waterproof claim.
- **Legal:** informational only that recording laws and headphone rules vary by place.

## Traceability

Every acceptance criterion maps to tasks in `tasks.md` via `_Requirements:_` annotations, and
`design.md` references requirement numbers where it explains how each is satisfied.
