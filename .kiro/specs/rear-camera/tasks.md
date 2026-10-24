# Implementation Plan — Whoosh Rear-Mounted Camera Recording

Small, ordered, verifiable tasks. **No code exists for this feature yet and none may be written
until the owner approves this spec** (`requirements.md`, `design.md`, this file).

Spec status: **APPROVED** by the iOS owner (October 24, 2026) with the recommended answers to O-CAM1–O-CAM6 (`design.md`, "Owner resolution").

This plan is separate from the ride-recording MVP plan (`../ride-recording-mvp/tasks.md`, tasks
1–28) and the crash-response plan (`../crash-response/tasks.md`). Task numbers here are independent;
cross-spec references say "MVP task N" or "crash-response task N".

## Conventions

- `(test-first)` — write failing unit tests from the referenced acceptance criteria, then
  implement until green (the existing `.kiro/hooks/test-first-before-task.json` applies).
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers (`B#` = Teammate B, `C#` = Role C).
- `_Parallel:_` names the parallel group (see "Parallel groups") or says what can run alongside.
- Each task is one reviewable commit or small PR. **Commits are made by the owner**, never by an
  automated agent unless asked.
- **Owner tags:** `[iOS]` iOS app owner · `[Teammate B]` vision/detection owner · `[Role C]`
  backend/data owner · `[Owner]` product decision.
- **Priority tags:** `[DEMO]` blocks the live demo · `[IMPORTANT]` expected but the demo can run
  without it · `[STRETCH]` valuable, never blocking · `[FUTURE]` documented follow-up.
- Run `scripts/test.sh` before marking a task done. Tasks touching real capture, the asset writer,
  brightness, background modes, notifications, Photos, or WatchConnectivity also need the device
  check named in the task and an entry in `manual-qa.md` (task 31).
- Layering is enforced by `scripts/privacy-check.sh` (task 1). New folders: `Services/Camera/`,
  `Services/Screen/`, `Services/Remote/`, `Features/Camera/`.
- **Copy rule for every task:** user-facing text says recording is for the rider's own records and
  detection is experimental; it never claims evidence, assured capture, or prevention. Phrase any
  disclaimer so it passes `scripts/privacy-check.sh` (for example "cannot guarantee detection").
- **No Swift is written by this spec's authoring job.** All code below is future work.

## Demo tiers

| Tier | What the judges see | Needs | Tasks |
| ---- | ------------------- | ----- | ----- |
| **Tier 0 — "It records"** (iOS only, no model, no watch) | Enable rear camera → Mount & frame (live preview, level, test recording) → Start → mount grace → screen goes black/dim with a red dot → ride → unlock with two fingers → **Save clip** → stop → summary shows the saved clip, plays it, deletes it. Works in airplane mode. | iOS tasks only | 0–2, 3–9, 11, 12, 15–23, 26, 31 |
| **Tier 1 — "It reacts"** | A simulated or real vehicle detection pins a clip automatically and an audio cue plays; clip labeled "Vehicle detected (experimental)". | Tier 0 + 10, 13, 14, 28, 29 (+ demo-mode simulated detector, or B's detector) | + 10, 13, 14, 28, 29, 32 |
| **Tier 2 — "It integrates"** | GPS continues with the screen locked; camera pause notice; B's real detector consuming frames; crash footage; watch spec started. | Tier 1 + 24, 25, B1–B3, 30, 34 | + 24, 25, 30, B1–B3 |

If the camera misbehaves on demo day, the ride still records (Never block a ride) and the MVP demo
path is unchanged.

---

## Phase 0 — Gate

- [x] 0. `[Owner]` `[DEMO]` Review and approve the spec; resolve open decisions
  - Read `requirements.md`, `design.md`, and this plan. Decide **O-CAM1** (watch), **O-CAM2**
    (background location), **O-CAM3** (default numbers), **O-CAM4** (retention), **O-CAM5** (audio),
    **O-CAM6** (detection auto-pin), or accept the recommended defaults, and record answers in
    `design.md` "Decisions".
  - Review the changed assumptions A–G and the steering edits (`product.md`, `privacy.md`,
    `tech.md`, `team-plan.md`).
  - Reconcile with the parallel `../demo-mode/` spec (Requirement 18.5) and with Teammate B on the
    frame-consumer contract (task 11).
  - _Verify:_ spec status changed to "Approved"; open decisions marked resolved.
  - _Requirements:_ 1, 11.5, 13.6, 18.5
  - _Parallel:_ none (gate)

## Phase 1 — Guardrails and pure core (no frameworks, test-first)

- [ ] 1. `[iOS]` `[DEMO]` Update `scripts/privacy-check.sh` for camera, screen, remote, and Photos
  - Replace rule 7 (camera access outside `Services/Detection`) with: capture/writer APIs
    (`AVCaptureSession`, `AVCaptureDevice`, `AVCaptureVideoDataOutput`, `AVCaptureAudioDataOutput`,
    `AVCaptureMovieFileOutput`, `AVAssetWriter`, camera/microphone authorization) only in
    `Services/Camera/`. **Remove** the `Services/Detection` allowance (detectors consume frames).
  - Add: `import Photos`/`PHPhotoLibrary` only in `Services/Camera/PhotosClipExporter.swift`;
    `import WatchConnectivity` only in `Services/Remote/`; `UIScreen` brightness writes and
    `isIdleTimerDisabled` only in `Services/Screen/` (temporarily allow `ActiveRideView` until task
    21 migrates it); Core Motion also allowed in `Services/Camera/`; files under `Services/Sync/` and
    `Services/Notification/` must not reference camera/clip/footage types; Models/Metrics must not
    import AVFoundation/CoreMedia/CoreVideo/Photos/CoreMotion; copy rule against claiming footage is
    evidence or that capture is assured (phrased to avoid colliding with rule 4).
  - Update the header comment. The `privacy-guard-on-save` hook already runs the script.
  - _Verify:_ run the script against temporary sample files under allowed and disallowed paths
    (for example `Whoosh/Services/Camera/…` allowed; `Whoosh/Features/Ride/…`, `Services/Detection/…`,
    `Services/Sync/…` flagged); delete the samples; the full run on the current tree still prints OK.
  - _Requirements:_ 16.9, 16.10, 4.9
  - _Depends on:_ 0
  - _Parallel:_ Group P0 (first; guards everything after)
  - _Note:_ this edits `scripts/`, which the spec-writing job did not touch; merge it before any
    camera code lands. Coordinate with crash-response task 2 (same file): whichever lands second
    merges the other's rules.

- [ ] 2. `[iOS]` `[DEMO]` Domain models and tuning constants (Foundation only)
  - Add the Models listed in `design.md` "Layering additions": `CaptureProfile` (with the three
    profiles), `CameraRecordingState`, `CameraStopReason`, `InterruptionReasonKind`, `SegmentInfo`,
    `ClipRecord`, `ClipReason`, `ClipState`, `PinRequest`, `PinWindow`, `NearMissEvent`,
    `RideCameraTuning` (every default and range from the design table), `ScreenMode`, `ThermalLevel`,
    `StorageStatus`, `CameraPermissionStatus`, `RideStatus`, `RideRemoteCommand`; additive
    `AlertKind` cases (`cameraInterrupted`, `cameraResumed`, `cameraStopped(reason)`, `clipSaved`,
    `clipNotSaved(reason)`, `phoneBatteryLow`).
  - Value types are `Equatable`, `Codable` where persisted, and `Sendable` where they cross actors.
    Models import Foundation only; time is `TimeInterval`/`Date`, never `CMTime`.
  - _Verify:_ models compile in the test target; tuning clamps every range; existing exhaustive
    switches over `AlertKind` (if any) still compile.
  - _Requirements:_ 3.2, 5.1, 5.4, 5.10, 6.2, 6.8, 12.1, 13.1, 13.4, 15.2
  - _Depends on:_ 0
  - _Parallel:_ after 0; P1 tasks 3–10 start once this lands

- [ ] 3. `[iOS]` `[DEMO]` `RingBufferPolicy` (pure, test-first)
  - Eviction function per `design.md`: bounds by duration **or** bytes, oldest unpinned first, never
    the open segment, pinned segments, or segments in a pending post-roll window; strict-greater
    trigger; `overBoundUnevictable` report; effective-cap shrink; out-of-order input.
  - Unit tests RB-1…8 (parameterized tables).
  - _Requirements:_ 5.4, 5.5, 5.10, 19.2
  - _Depends on:_ 2
  - _Parallel:_ Group P1

- [ ] 4. `[iOS]` `[DEMO]` `ClipWindowPolicy` and coalescing (pure, test-first)
  - Window computation: pre/post by source, snap outward to segment boundaries, exact in/out
    offsets, clamp to ride start, `pendingUntil`, gap flag, no-segments case; coalescing with the
    gap tolerance and the max clip duration (shared boundary segment); pinned-cap handling for
    manual vs auto sources.
  - Unit tests CW-1…10.
  - _Requirements:_ 6.2, 6.4, 6.5, 6.6, 6.9, 11.7
  - _Depends on:_ 2
  - _Parallel:_ Group P1

- [ ] 5. `[iOS]` `[IMPORTANT]` Thermal, storage, battery policies and profile selector (pure, test-first)
  - `ThermalPolicy` (step-down order fps → resolution, critical stop, hysteresis step-up, consumer
    half-rate at serious), `StoragePolicy` (start/warn/stop, effective ring cap), `BatteryPolicy`
    (suggest Efficient ≤ 20%, stop ≤ 8% unplugged, charging override, Low Power Mode ⇒ Efficient),
    `CaptureProfileSelector` (requested ∩ supported formats ∩ adjustments, fallback, unavailable).
  - Unit tests TP-1…8, SP-1…6, CS-1…8 with a controllable `Clock`.
  - _Requirements:_ 3.2, 12.1, 12.2, 12.3, 12.6, 19.2
  - _Depends on:_ 2
  - _Parallel:_ Group P1

- [ ] 6. `[iOS]` `[DEMO]` `FrameDropPolicy` (pure, test-first)
  - Rate limiting with jitter tolerance, backward clock, large gap/discontinuity, invalid max fps,
    capture-rate ≤ max.
  - Unit tests FD-1…8 (the design's table, one row each).
  - _Requirements:_ 4.4, 4.5, 4.8
  - _Depends on:_ 2
  - _Parallel:_ Group P1 · **Teammate B can review this table in parallel**

- [ ] 7. `[iOS]` `[DEMO]` `CameraStateMachine` reducer (pure, test-first)
  - State × event × context → state × effects (as data) for all 24 rows of the design's table,
    including permission/storage start guards, retry limits, interruption and resume, policy stops
    and auto-resume, writer failure restart-once, ride end teardown, record-while-paused, and
    undefined transitions as no-ops.
  - Unit tests CM-1…24; property check: no event sequence starts a session while the permission is
    not `authorized`; no effect ever touches GPS.
  - _Requirements:_ 5.9, 11.2, 11.3, 12.1–12.3, 17.1, 17.2, 19.2
  - _Depends on:_ 2, 5
  - _Parallel:_ Group P1b (after 5)

- [ ] 8. `[iOS]` `[DEMO]` `ScreenModeStateMachine` and `BrightnessGuard` (pure, test-first)
  - Reducer for all 15 rows (grace, dim, two-finger unlock, extend, re-dim, resign-active, resume,
    crash forcing, ride end, external brightness change, launch guard restore); `BrightnessGuard`
    restore-target function.
  - Unit tests SM-1…15, BG-1…6 with a controllable `Clock`.
  - _Requirements:_ 10.2, 10.3, 10.5, 10.7, 13.7, 19.2
  - _Depends on:_ 2
  - _Parallel:_ Group P1

- [ ] 9. `[iOS]` `[DEMO]` `LevelCalculator` and `ReadinessEvaluator` (pure, test-first)
  - Roll/pitch from a gravity vector and mount orientation with thresholds; checklist evaluation
    (pass/warn/block per row) from permission, storage, battery, Low Power Mode, thermal, location,
    scene brightness, and level inputs.
  - Unit tests LV-1…6, RE-1…10.
  - _Requirements:_ 9.1, 9.3, 12.2, 19.2
  - _Depends on:_ 2, 5
  - _Parallel:_ Group P1b

- [ ] 10. `[iOS]` `[IMPORTANT]` `NearMissPolicy`, `NearMissUploadMapper`, `AlertRoutingPolicy`, `StatusThrottle` (pure, test-first)
  - `NearMissPolicy`: confidence threshold, cooldown, per-ride cap, storage refusal, no-clip event.
    `NearMissUploadMapper`: event → contract fields only (ride id, time, lat/lon, kind, confidence,
    position hint); assert no clip/video/thumbnail field survives. `AlertRoutingPolicy`: kind ×
    channel availability × app context → ordered sinks, with cooldowns. `StatusThrottle`: on-change
    plus heartbeat.
  - Unit tests NM-1…8, UP-1, AR-1…8.
  - _Requirements:_ 13.3, 15.1, 15.3, 19.2
  - _Depends on:_ 2
  - _Parallel:_ Group P1

## Phase 2 — Seams, fakes, and stores

- [ ] 11. `[iOS]` `[DEMO]` Frame pipeline and the consumer contract — **unblocks Teammate B** (test-first)
  - Define `VideoFrame`, `FrameConsumer` (exact members in `design.md`), `FrameSink`, and the
    concrete `FramePipeline` (registry, per-consumer single-slot latest-wins mailbox and driver,
    rate limiting through `FrameDropPolicy`, stats), plus `FakeCameraSource` (emits synthetic frames
    on command and at a scripted rate) and a `RecordingFrameStats`/test consumer.
  - Hold a **contract freeze** with Teammate B and Role C (3-way OK, like `HazardDetection`): the
    `FrameConsumer`/`VideoFrame` shapes and the backpressure rule do not change without agreement.
  - Document the Swift 6 sendability approach for the pixel buffer wrapper.
  - Unit tests FP-1…8 (zero-consumer no-op, slow consumer, independence, add/remove while running,
    busy-drop counts, retention cap, discontinuity flag, ordering).
  - _Requirements:_ 4.1–4.8, 4.10, 19.2
  - _Depends on:_ 2, 6
  - _Parallel:_ Group P2 · **Teammate B starts B1 as soon as this merges**

- [ ] 12. `[iOS]` `[DEMO]` Camera seams with fakes (test-first)
  - Protocols and fakes: `CameraPermission`, `CameraCapturing` (+ `FakeCameraCapture` that drives
    state/events and feeds a pipeline), `SegmentRecording` (+ fake), `SegmentStore` (+ in-memory
    fake), `ClipRepository` (+ in-memory), `ScreenController` (+ fake), `MountLevelSensing` (+ fake).
  - Contract doc comments: off-main, non-blocking, never stops GPS, no footage leaves the device.
  - _Verify:_ fakes behave as scripted; each fake's scripting API is covered by a small test.
  - _Requirements:_ 1.7, 2.2, 3.1, 5.10, 8.9, 19.2
  - _Depends on:_ 2
  - _Parallel:_ Group P2

- [ ] 13. `[iOS]` `[IMPORTANT]` Eyes-free seams with fakes (test-first)
  - `RideStatus` builder (`RideStatusPublisher`), `RideRemoteControlling` + `NoopRideRemote` +
    `FakeRideRemote`, `RideRemoteBridge` (commands → existing `RideSessionViewModel` intents, save
    clip, cancel crash countdown; `stop` ignored without `confirmedByHold`), `AlertSink` +
    `FakeAlertSink`, `FanOutAlertManager` (conforms to the unchanged `AlertManager`).
  - Unit tests RC-1…6 and fan-out routing through `AlertRoutingPolicy`.
  - _Requirements:_ 13.1–13.5, 13.8
  - _Depends on:_ 2, 10
  - _Parallel:_ Group P2 (needs the pure policies from 10)
  - _Note:_ the watch app is task 34; WatchConnectivity is not imported anywhere in this spec.

- [ ] 14. `[iOS]` `[IMPORTANT]` Update the `HazardDetector` seam docs; `DetectionCoordinator` (test-first)
  - Update doc comments on `HazardDetector` and `NoopDetector` to the new contract (frames only via
    `FrameConsumer`; no capture ownership; permission belongs to rear camera recording). The
    `HazardDetection` struct is **not** changed.
  - Add `FakeHazardDetector` (emits on command) and `DetectionCoordinator` (registers a detector
    that is also a `FrameConsumer` with the pipeline while the camera is `recording`/`degraded` and
    detection is enabled; routes detections to `NearMissPolicy`, alerts, and pinning via protocols).
  - Unit tests: registration lifecycle, no registration while the camera is off, detection routing
    with fakes, `Noop` stays inert.
  - _Requirements:_ 4.9, 15.1, 15.4, 15.5
  - _Depends on:_ 10, 11, 12
  - _Parallel:_ Group P2b

- [ ] 15. `[iOS]` `[DEMO]` `FileSegmentStore` and SwiftData `ClipRepository` (test-first)
  - `FileSegmentStore` over a temp directory: register/list/delete segments, hard-link pin with
    copy fallback, bytes used, free-space query behind a protocol, orphan purge, backup-exclusion
    and protection attributes. `SwiftDataClipRepository` (+ `ClipRecordEntity`) with the same
    contract as the in-memory fake, including `expired(now)` and `deleteAll(rideId)`.
  - Tests against temp directories and an in-memory `ModelContainer`: ordering, delete real files,
    corrupt-record skip, adding the new `@Model` does not disturb existing ride data (device check in
    task 31).
  - _Requirements:_ 5.7, 5.8, 8.4, 8.5, 8.6, 8.9, 17.3
  - _Depends on:_ 2, 12
  - _Parallel:_ Group P2

- [ ] 16. `[iOS]` `[DEMO]` `ClipPinner`, manual save, and thumbnails (test-first, fakes)
  - Pinning orchestration over `ClipWindowPolicy`, `SegmentStore`, `ClipRepository`: pending
    post-roll protection, flip to `saved`/`endedEarly`, coalescing into existing clips, debounce,
    "nothing to save", storage-full refusal, ride-end finalization; `ClipThumbnailer` behind a
    protocol (fake in tests).
  - Unit tests MAN-1…4, CL-1…6 (retention sweep, cascade), FB-style "never blocks" checks.
  - _Requirements:_ 6.1–6.9, 8.4, 8.5, 8.7
  - _Depends on:_ 4, 12, 15
  - _Parallel:_ Group P2b

## Phase 3 — Real capture, recording, and ride integration (device checks)

- [ ] 17. `[iOS]` `[DEMO]` `CameraCaptureService` (AVFoundation)
  - Back wide camera, profile application (formats, fps, HEVC), stabilization, orientation lock to
    the mount orientation, exposure bounds, far-range continuous autofocus, thermal/system-pressure
    observation, interruption and runtime-error observation mapped to events, preview host for
    Mount & frame, full teardown. All off the main actor; callbacks on the main actor. Feeds
    `FramePipeline` and the recorder from one video data output with late-frame discarding.
  - _Verify (device):_ preview and frames at both profiles; frame-rate change applied live;
    resolution change at a segment boundary; the camera indicator turns off on teardown;
    interruption callbacks on lock and on a call; record the actual start latency and drop counts
    in `manual-qa.md`.
  - _Requirements:_ 3.1–3.8, 4.1, 4.3, 12.1
  - _Depends on:_ 5, 11, 12
  - _Parallel:_ Group P3 (with 18 in the same device session; 17 and 18 are separate PRs)

- [ ] 18. `[iOS]` `[DEMO]` `AssetWriterSegmentRecorder` and ring manager
  - One writer per segment (HEVC/H.264 fallback, key-frame interval, movie fragments, orientation
    transform), rotation on the boundary frame without blocking capture, drop-when-not-ready with
    counters, segment registration, ring eviction via `RingBufferPolicy` after each segment, ride-end
    cleanup, launch-time orphan purge, file protection and backup exclusion.
  - _Verify (device):_ segment length and gap measurement (≤ 1 frame interval), playable files after
    force-killing the app mid-segment, storage stays within caps over a 15-minute run, no main-thread
    stalls (Instruments). Record results in `manual-qa.md`.
  - _Requirements:_ 5.1–5.8, 5.10, 19.4
  - _Depends on:_ 3, 12, 15, 17 (capture) — logic can be developed against the fake recorder first
  - _Parallel:_ Group P3

- [ ] 19. `[iOS]` `[DEMO]` `CameraRecordingCoordinator`, `RideCameraBridge`, composition
  - `@Observable` main-actor coordinator driving the `CameraStateMachine` effects: start/stop with
    the ride (read-only bridge over `RideSessionViewModel`; ride engine untouched), thermal/storage/
    battery polling through the pure policies, policy stops and auto-resume, writer failure restart,
    status publishing, `recordWhilePaused`. Wire into `AppEnvironment` (live and preview with fakes).
  - Unit tests: coordinator with `FakeCameraCapture`, `FakeSegmentRecorder`, a controllable `Clock`
    and fake power/thermal/storage inputs (re-using `PowerStateMonitoring` where it fits).
  - _Verify (device):_ a ride with the camera on records segments and a ride with it off is
    unchanged; a camera failure never changes the ride state or GPS points.
  - _Requirements:_ 1.2–1.4, 5.9, 12.1–12.4, 17.1, 17.2, 17.4
  - _Depends on:_ 7, 16, 17, 18
  - _Parallel:_ sequential after 17/18

- [ ] 20. `[iOS]` `[DEMO]` Permission flow, Settings rows, and `project.yml`
  - `CameraPermission` AV implementation; first-enable explanation sheet (what is recorded, stays on
    device, other people may appear, local laws vary — informational); "Rear camera" Settings section
    (toggle off by default, Quality, Ride mode, Buffer length, storage used, retention, Delete all
    clips); denied/restricted states with Open Settings.
  - Update the usage strings in `project.yml` (and regenerate once, owner-run): camera string changes
    from "experimentally detect approaching vehicles" to a recording statement
    ("Whoosh uses the rear camera to record video of the road behind you during rides. Video is saved
    on your device and is not uploaded."); add the microphone string only with task 33.
  - Unit tests PERM-1…4 and the Settings view model.
  - _Requirements:_ 2.1–2.7, 16.2, 16.7, 18.1
  - _Depends on:_ 12
  - _Parallel:_ Group P3 (UI work independent of 17/18)

- [ ] 21. `[iOS]` `[DEMO]` Screen control, `RideModeController`, and ride mode view
  - `UIKitScreenController` (brightness via the active window scene's screen, idle timer, system
    brightness change notifications), `DimGuardStore` (persisted guard) and launch-time restore;
    `RideModeController` (`@Observable`) driving the reducer; `RideModeView` overlay inside the ride
    cover: mount grace, black screen, red dot with slow shift, touch lock, two-finger long-press
    unlock, VoiceOver custom unlock action, toasts, amber trouble dot. **Migrate**
    `ActiveRideView`'s direct idle-timer calls behind `ScreenController`, then drop the temporary
    allowance from task 1.
  - _Verify (device):_ brightness restored on every exit (unlock, stop, lock button, app switch,
    force-quit then relaunch); Auto-Brightness behavior; wet/gloved two-finger unlock reliability;
    OLED look in a dark room; no hidden system indicators.
  - _Requirements:_ 10.1–10.8, 16.6, 19.1
  - _Depends on:_ 8, 12
  - _Parallel:_ Group P3

- [ ] 22. `[iOS]` `[DEMO]` Mount & frame screen
  - `MountAndFrameView(+VM)`: preview (`CameraPreviewView` representable over the service's preview
    host), level indicator (Core Motion sensor in `Services/Camera/`), framing guide, test recording
    with playback and stats, readiness checklist from `ReadinessEvaluator`, profile/orientation/ride
    mode choices, "Start ride", "Start without framing", "Ride without camera". Reachable from Home's
    rear-camera entry and from Start Ride when the feature is on. Mount grace hands off to ride mode.
  - Previews and tests use the fake camera.
  - _Verify (device):_ level accuracy vs a physical level; test recording file written and played;
    leaving the screen tears everything down.
  - _Requirements:_ 9.1–9.7, 1.2, 18.2
  - _Depends on:_ 9, 12, 17, 20 (preview needs 17 on device; UI can proceed against fakes)
  - _Parallel:_ Group P3

- [ ] 23. `[iOS]` `[IMPORTANT]` Ride-screen integration
  - On `ActiveRideView` (used when ride mode is off or unlocked): "Recording video" chip (icon +
    text), a "Save clip" control, camera-trouble banners (calm, actionable), VoiceOver announcements
    for camera state changes. Preserve the three-numbers rule; the existing "Rear detection off"
    chip stays until a real detector exists.
  - Update the Home placeholder area with the "Rear camera recording" entry (Requirement 18.2).
  - _Requirements:_ 18.2–18.4, 10.8, 19.1
  - _Depends on:_ 19, 21
  - _Parallel:_ Group P4

- [ ] 24. `[iOS]` `[IMPORTANT]` Background location (open decision O-CAM2)
  - Declare `UIBackgroundModes: location` in `project.yml` (regenerate once, owner-run); extend
    `LocationTracking` additively with a way to request background updates, set only while a ride is
    active and started from the foreground; `CoreLocationTracker` enables the background-updates flag
    and the background-location indicator (or `CLBackgroundActivitySession`, whichever is chosen on
    the device test); `FakeLocationTracker` records the request; update the "no background modes"
    doc comments and `RideTuning` if a flag is needed. **No Always authorization prompt.**
  - Unit tests with fakes: background updates requested on ride start, cleared on stop/finish, never
    requested while idle.
  - _Verify (device):_ lock the phone for 10+ minutes mid-ride; points continue; the indicator shows;
    permission stays When-In-Use; stopping the ride ends tracking; battery impact noted.
  - _Requirements:_ 11.5, 11.8
  - _Depends on:_ 0 (O-CAM2)
  - _Parallel:_ Group P3 (independent of camera work; can be done on its own)

- [ ] 25. `[iOS]` `[IMPORTANT]` Interruption, lock, and "camera paused" handling
  - Finalize the open segment inside a short background task on interruption/resign-active; resume
    on return with a new segment and discontinuity flag; local notification (lazy authorization after
    an in-app explanation) when the camera is paused over the threshold; remote/audio alert;
    summary notes gaps; pin windows across gaps flagged.
  - _Verify (device):_ lock mid-ride → file finalized and playable, notice arrives (and mirrors to a
    paired watch when locked), return resumes recording; incoming call and Focus behavior recorded.
  - _Requirements:_ 11.1–11.4, 11.6, 11.7, 17.1
  - _Depends on:_ 19, 24, 13
  - _Parallel:_ sequential after 19

- [ ] 26. `[iOS]` `[DEMO]` Clips in summary and history; cascade; retention
  - `ClipListView` in the summary (also history detail): thumbnail, time into the ride, duration,
    reason icon + text, clip count on history rows; `ClipPlayerView` (AVKit); delete one (confirm),
    delete all for the ride; ride deletion (swipe and "Delete all rides") cascades to clips through a
    small cleanup hook; Settings storage used and "Delete all clips"; launch/foreground retention
    sweep ("expires in N days").
  - Unit tests with in-memory repositories (cascade, sweep, counts).
  - _Verify (device):_ playback of a multi-segment clip; deletion removes files.
  - _Requirements:_ 8.1–8.7, 8.9
  - _Depends on:_ 16, 20
  - _Parallel:_ Group P3

- [ ] 27. `[iOS]` `[IMPORTANT]` Photos export
  - `ClipExporting` + `PhotosClipExporter` (the only Photos file): single-MP4 passthrough export into
    `tmp/`, add-only authorization requested at the first explicit export, copy-not-move, temp cleanup,
    plain failure messages. "Save to Photos" action on a clip only.
  - Add `NSPhotoLibraryAddUsageDescription` (purpose-specific).
  - _Verify (device):_ export works with add-only access; denial leaves the clip intact.
  - _Requirements:_ 2.6, 8.8, 16.7
  - _Depends on:_ 26
  - _Parallel:_ Group P4

- [ ] 28. `[iOS]` `[IMPORTANT]` Detection → near-miss → clip
  - Persist `NearMissEvent` locally with the ride; `DetectionCoordinator` pins detection clips
    (cooldown, per-ride cap, storage refusal) and links the local clip id; labels in the clip list
    ("Vehicle detected (experimental)"). Off by default until Teammate B's measured thresholds exist
    (O-CAM6); runs end-to-end today with `FakeHazardDetector` or the demo-mode simulated detector.
  - _Requirements:_ 6.1, 6.6, 15.1–15.5, 18.5
  - _Depends on:_ 14, 16, 19
  - _Parallel:_ Group P4

- [ ] 29. `[iOS]` `[IMPORTANT]` Alert sinks and wiring
  - `PhoneAudioAlertSink` (mixing audio category, short tones/speech for the routed kinds; honest
    about speaker/wind limits), `LocalNotificationAlertSink`, composition of `FanOutAlertManager` in
    `AppEnvironment` replacing `StubAlertManager`; audio cues for clip saved/not saved and camera
    state. Haptic phone sink only for when ride mode is off (pocket use).
  - _Verify (device):_ audio mixes with music, works with the silent switch policy decided, no effect
    on recording; routing matches the design's table.
  - _Requirements:_ 13.3–13.5, 13.8, 6.7
  - _Depends on:_ 13
  - _Parallel:_ Group P4

- [ ] 30. `[iOS]` `[STRETCH]` Crash-response integration: real `FootageBuffer`, forced un-dim, wrist cancel
  - `ClipFootageBuffer` implements crash-response's `FootageBuffer` (task 34 there): `preserve`
    returns the clip reference immediately; `delete` removes the clip; delete from the crash log
    works. When the crash coordinator starts a countdown: ride mode exits to full brightness and
    unlock (screen row 10), `RideStatus.crashCountdownDeadline` is published, `cancelCrashCountdown`
    is accepted from the remote bridge; consent copy mentions that without a watch the phone must be
    reachable to cancel.
  - Short note recorded in crash-response `design.md` Risks (done in this job); any change to its
    other documents goes through the owner.
  - _Requirements:_ 7.1–7.5, 13.7
  - _Depends on:_ 16, 19, 21, 13 and crash-response tasks 7, 12, 22
  - _Parallel:_ after the crash coordinator exists

- [ ] 31. `[iOS]` `[DEMO]` Device QA, budgets, and the measurement protocol
  - Create `.kiro/specs/rear-camera/manual-qa.md` (checklist from the design's manual list) and run
    it; execute the measurement protocol (S0–S3, shade and sun) and fill "Measured results" in
    `design.md`; adjust defaults (profile, Efficient auto-switch, caps) from real numbers; confirm the
    *(verify)* items (fragment recovery, brightness restore, protection class, hard links, background
    GPS, free-space API).
  - _Requirements:_ 12.5, 19.3, 19.5
  - _Depends on:_ 17, 18, 19, 21, 24 (and 25 for interruption rows)
  - _Parallel:_ rolling; start with 17/18 and finish last

- [ ] 32. `[iOS]` `[IMPORTANT]` Demo-mode coordination
  - Agree with the `../demo-mode/` spec on: a demo path that runs the pipeline from
    `FakeCameraSource`/`FileFrameSource` (no bike needed); simulated `HazardDetection` flowing through
    the same near-miss and pinning path; demo-labeled clips (`demo` reason) and their deletion; no
    network. Implement only the iOS-side glue not owned by that spec.
  - _Requirements:_ 18.5, 15.5
  - _Depends on:_ 11, 14, 28 and the demo-mode spec tasks
  - _Parallel:_ coordination task; no code until both specs are approved

## Phase 4 — Stretch and future (never block the demo)

- [ ] 33. `[iOS]` `[STRETCH]` Optional audio recording
  - Off by default; microphone permission and string only when enabled; audio input/output on its
    own queue; audio flag on segments and clips; video-only fallback on denial; guidance copy
    (conversations may be recorded; laws vary — informational).
  - _Requirements:_ 14.1–14.4, 2.5
  - _Depends on:_ 18, 20

- [ ] 34. `[iOS]` `[FUTURE]` Apple Watch companion spec (open decision O-CAM1)
  - Write `.kiro/specs/watch-companion/` (requirements, design, tasks) against the seams from task
    13: feasibility spike first (keeping the watch app alive with a workout session, reachability and
    latency, haptic patterns), then the watch UI (pause/resume, save clip, hold-to-stop, live time/
    distance, camera/storage/battery state, crash-countdown cancel) and the WatchConnectivity
    implementation in `Services/Remote/` plus a watch `AlertSink`.
  - _Requirements:_ 13.6
  - _Depends on:_ 13

- [ ] 35. `[iOS]` `[STRETCH]` `FileFrameSource` (replay a recorded clip through the pipeline)
  - Plays a video file at real time into `FramePipeline` with correct timestamps, orientation, and
    discontinuity flags, so a detector can be tested on real footage without riding and demo mode can
    show the pipeline without a bike.
  - _Requirements:_ 4.10, 18.5
  - _Depends on:_ 11
  - _Parallel:_ Group P2b · **Teammate B's offline evaluation uses this (B2)**

- [ ] 36. `[iOS]` `[STRETCH]` Handlebar Bluetooth shutter remote → Save clip
  - Observe hardware button events while the camera is active and map a configured button to "Save
    clip" (no watch needed). Verify the API behavior on iOS 17/18 first.
  - _Requirements:_ 6.1, 13.8
  - _Depends on:_ 16, 19

- [ ] 37. `[iOS]` `[STRETCH]` Post-ride "Save last N minutes" and "Keep" for clips
  - On the summary, for two minutes after Stop, offer to save the last 5 minutes before the ring is
    cleared; per-clip "Keep" exempting it from retention.
  - _Requirements:_ 5.7, 8.7
  - _Depends on:_ 16, 26

- [ ] 38. `[iOS]` `[STRETCH]` Pick-up auto-unlock for ride mode
  - Core Motion detects the phone leaving the mount (large orientation change while slow) and raises
    the `pickedUp` event to unlock ride mode.
  - _Requirements:_ 10.3
  - _Depends on:_ 21

- [ ] 39. `[iOS]` `[FUTURE]` Lens options and detect-only mode
  - Ultra-wide lens option and manual exposure; detect-only mode (camera session without writing
    video). Needs measurements and an owner decision.
  - _Requirements:_ 3.1 (extension)
  - _Depends on:_ 31

- [ ] 40. `[iOS]` + `[Role C]` `[FUTURE]` Near-miss event sync (no video)
  - After ride sync exists (MVP task 28) and Role C marks the `near_misses` contract Agreed, upload
    mapped events (via `NearMissUploadMapper`) behind the ride-sync opt-in; clip ids and video are
    never part of the payload; deleting a ride deletes its remote near-misses.
  - _Requirements:_ 15.3, 16.4
  - _Depends on:_ 28, C-R1 and MVP task 28

---

## Teammate B tasks (`[Teammate B]`) — vision / detector

- [ ] B1. `[Teammate B]` `[DEMO]` Make the detector a `FrameConsumer`
  - Implement `HazardDetector` **and** `FrameConsumer` in one type: declare `maxFramesPerSecond`
    (expected ≤ 10), pixel format, and dimension hint; process one frame at a time; copy if history
    is needed; reset temporal state on the discontinuity flag; set `HazardDetection.timestamp` from
    `VideoFrame.capturedAt`. Never create a capture session, never request permission, never write
    video.
  - _Verify:_ runs against `FakeCameraSource` in the app's test target and in B's own harness.
  - _Requirements:_ 4.1–4.9, 15.1
  - _Depends on:_ 11 (merged contract)
  - _Parallel:_ starts right after task 11; independent of every other iOS task

- [ ] B2. `[Teammate B]` `[IMPORTANT]` Offline evaluation on real mounted footage
  - Use clips recorded by the app (or `FileFrameSource`, task 35) from a real seat-post mount to
    evaluate the model; report precision/recall and false-positive rate per hour of riding; make no
    reliability claims.
  - _Depends on:_ B1, 18 (real footage) or 35

- [ ] B3. `[Teammate B]` `[IMPORTANT]` Thresholds and measured numbers for `NearMissPolicy`
  - Provide the recommended confidence threshold, cooldown, and inference cost (ms, thermal/battery
    impact) so iOS can set defaults and the honest copy; consumed by tasks 28 and 31.
  - _Depends on:_ B2

## Role C tasks (`[Role C]`) — database (events only, no video)

- [ ] C-R1. `[Role C]` `[IMPORTANT]` Confirm `near_misses` for the camera spec
  - Review `supabase-contract.md` `near_misses` against `NearMissUploadMapper`: fields are ride id,
    occurred-at, latitude, longitude, kind, confidence, position hint; **no column for video, clip id,
    thumbnail, or frame**; RLS own-rows (same pattern as `rides`); deletion cascades with the ride.
    Mark the table section Agreed when ready.
  - _Depends on:_ none (documentation); needed by task 40

- [ ] C-R2. `[Role C]` `[STRETCH]` Website near-miss markers
  - Show near-miss events as markers on the route map (fixture first); no video, no thumbnails.
  - _Depends on:_ C-R1

---

## Parallel groups

| Group | Tasks | Notes |
| ----- | ----- | ----- |
| **P0** | 0, 1 | Gate; privacy script lands before any camera code |
| **P1** | 2 → then 3, 4, 5, 6, 8, 10 in parallel | Distinct pure files; no framework dependencies |
| **P1b** | 7, 9 | After 5 (policy inputs) |
| **P2** | 11, 12, 13, 15 | After their pure inputs; 11 first (unblocks Teammate B) |
| **P2b** | 14, 16, 35 | After 11/12/15 |
| **Teammate B** | B1 after 11; B2/B3 later | Fully parallel with iOS tasks 12–22 |
| **Role C** | C-R1, C-R2 | Fully parallel; never blocks iOS |
| **P3 (device)** | 17 + 18 (device session), 20, 21, 22, 24, 26 | UI tasks 20/21/22/26 proceed on fakes while 17/18 are developed; 24 is independent of the camera |
| **P4** | 23, 27, 28, 29 | After 19/21/26/13 |
| **Rolling** | 31 | Starts with 17/18, ends last |
| **Sequential chain** | 17/18 → 19 → 25 | Camera hot path |
| **Coordination** | 0, 11 (freeze), 32 | Cross-spec/team agreements |

Two people can work in parallel with no merge pain: **iOS owner** on the pure core and
fakes (P1/P2) then capture/recording (P3); **a second contributor** (or the same person later) on
UI tasks 20–23 and 26 using the fake camera. Teammate B and Role C are independent after the
contract freeze.

## Proposed order of implementation

1. **Gate:** 0 (decisions) and 1 (privacy script) first; B and C pick up their review items in
   parallel.
2. **Pure core:** 2 → 3, 4, 5, 6, 8, 10 in parallel → 7, 9.
3. **Unblock the team:** 11 (frame pipeline + contract freeze) immediately; then 12, 15, 13, 14.
4. **Make it record:** 16 (pinning logic on fakes) alongside 17 → 18 → 19.
5. **Make it usable:** 20 → 21 → 22 (permission, ride mode, Mount & frame), then 26 (clips) and 23.
6. **Make it robust:** 24 (background GPS), 25 (interruptions), 31 (device QA and budgets).
7. **Make it react:** 28, 29, 32 (detection → clips, audio cues, demo glue).
8. **Integrate and extend:** 27 (export), 30 (crash footage), then 33–40 as time allows.

Critical path to the Tier 0 demo: 0, 2, 3, 4, 7, 11, 12, 15, 16, 17, 18, 19, 20, 21, 22, 26, 31.
Critical path to Tier 1 adds 10, 13, 14, 28, 29 (and the demo-mode simulated detector or B1).

## Kiro hooks

- **Existing, still sufficient:** `privacy-guard-on-save` runs `scripts/privacy-check.sh` on every
  saved Swift file; after task 1 it enforces the camera, screen, remote, Photos, and network-vs-footage
  rules. `run-tests-after-task` and `test-first-before-task` apply unchanged.
- **Optional new hooks (not created in this job; add only if wanted):**
  - `camera-hot-path-reminder` — `PreTaskExec` reminder for tasks 17–19 that nothing on the capture
    queue may block on a consumer, file I/O, or the main actor.
  - `brightness-restore-guard` — after saving `Services/Screen/` or ride-mode files, run only the
    screen-mode and brightness-guard tests.

## Definition of done (per task)

1. Code matches the layering table (no illegal imports); framework access is behind a protocol with
   a fake; capture APIs only in `Services/Camera/`.
2. New or changed logic has unit tests from the referenced acceptance criteria; the full suite is
   green (`scripts/test.sh`).
3. Device verification done and logged in `manual-qa.md` where the task calls for it; numbers
   recorded in `design.md` "Measured results" where the task measures.
4. No new first-party compiler warnings.
5. Privacy invariants intact: footage local-only, excluded from backups, never in a network layer or
   a message; permissions requested only at the moment of use; honest copy passing
   `scripts/privacy-check.sh`.
6. A camera or consumer failure never changes ride state or GPS points (assert in a test where the
   task touches the coordinator).
7. Camera trouble is never silent: the relevant alert/indicator path is exercised in a test or a QA
   row.

## Traceability (requirement → tasks)

| Req | Tasks |
| --- | ----- |
| 1 Scope and flow | 0, 19, 22, 23 |
| 2 Permissions | 12, 20, 27, 33 |
| 3 Capture service | 2, 5, 12, 17 |
| 4 Frame pipeline | 6, 11, 14, 17, 35, B1 |
| 5 Segments and ring | 2, 3, 7, 15, 18 |
| 6 Saving clips | 4, 10, 16, 28, 29, 36 |
| 7 Crash footage | 16, 30 |
| 8 Clip management | 15, 16, 26, 27, 37 |
| 9 Mount & frame | 9, 22 |
| 10 Ride mode | 8, 21, 38 |
| 11 Locked/backgrounded; background location | 7, 16, 24, 25 |
| 12 Thermal/battery/storage | 5, 7, 9, 19, 31 |
| 13 Eyes-free seams | 10, 13, 29, 30, 34 |
| 14 Audio | 33 |
| 15 Near-miss events | 10, 14, 28, 40, B1, B3, C-R1 |
| 16 Privacy and copy | 1, 20, 26, 40 |
| 17 Resilience | 7, 15, 18, 19, 25 |
| 18 Settings/Home/demo-mode | 20, 23, 28, 32, 35 |
| 19 Accessibility/testability | 3–10, 21, 31 |
