# Design — Whoosh Rear-Mounted Camera Recording

**Status: APPROVED by the iOS owner (October 24, 2026)** with the recommended answers to O-CAM1–O-CAM6 (`design.md`, "Owner resolution"). This document contains **no source code**
by design: the owner requires requirements, design, and tasks to be reviewed before any
implementation. Types, protocols, and state machines are described in tables and diagrams; code
is written later, task by task, test-first (`tasks.md`).

## Overview

Rear-mounted recording adds a camera subsystem next to the finished ride engine. It follows the
existing architecture: MVVM + service protocols, the injected `Clock`, explicit state machines,
fakes for every framework touchpoint, pure policy functions in `Metrics/`, and a composition root
that wires concrete types. **`RideSessionViewModel` is not modified**; a read-only bridge observes
it (the same pattern the approved crash-response design uses).

```
                         ┌──────────────── Eyes-free surfaces (watch spec, later) ────────────────┐
                         │  RideStatus ▶ RideRemoteControl ◀ commands   AlertSink(s) ◀ FanOutAlertManager
                         └───────────────────────────────▲────────────────────────▲───────────────┘
                                                         │                        │
 CameraPermission ─▶ CameraRecordingCoordinator (@Observable, MainActor; pure reducer + thermal/storage/battery policies)
                         │ start/stop/profile                       │ pin(source, time)        ▲ RideCameraBridge (read-only
                         ▼                                          ▼                          │ view of RideSessionViewModel)
 CameraCaptureService ─▶ FramePipeline ─▶ FrameConsumer(s)      ClipPinner ─▶ ClipRepository (SwiftData) + SegmentStore (files)
 (AVFoundation, off-main)    │  └─ latest-wins mailboxes            ▲   ▲   ▲
        │                    ▼                                       │   │   └─ crash event ─ ClipFootageBuffer (FootageBuffer)
        └─▶ SegmentRecorder (AVAssetWriter, rotating)  ─▶ ring buffer ┘   └──── manual save (phone / watch)
                                                                       └──────── detection ─ DetectionCoordinator ─ NearMissPolicy
                                                                                     ▲ HazardDetector (Teammate B; a FrameConsumer)
 RideModeController (@Observable) ─ ScreenController (UIKit brightness, idle timer) ─ touch lock overlay
```

### Revisability note

AVFoundation capture, the asset writer, PhotoKit export, WatchConnectivity, and UIKit screen
control are each behind a protocol with a fake and can be swapped with localized change. All
numeric values are tuning defaults in one `RideCameraTuning` type and are **hypotheses to be
measured** on the iPhone 14 (tagged *(verify)*). Items marked **OPEN** need an owner decision.

---

## Changed assumptions — reasoning (A–G)

The one-line table is in `requirements.md`. This section records the consequences.

### A. The phone is rear-mounted and unreachable

- The screen faces the rider's back. Nothing on it can be read or tapped while riding. Anything
  the MVP active-ride screen did *during* a ride (three numbers, Pause, hold-to-stop, banners) must
  be reachable another way or consciously dropped.
- **Start before mounting.** The ride is started and the camera framed on the phone (Mount &
  frame), then a **mount grace** countdown lets the rider clip the phone on before the screen dims.
  Starting the ride from the wrist is deliberately *not* a v1 command: a ride started without
  framing is the likeliest cause of useless footage.
- **Haptics on a seat post are not felt.** Core Haptics through the frame of a bike is unreliable;
  the product's "haptic alerts" idea needs a body-worn actuator. **Recommendation (O-CAM1): an
  Apple Watch companion** as the in-ride control and alert surface (pause/resume, save clip, stop,
  live time/distance, camera health, wrist haptics, crash-countdown cancel) over WatchConnectivity,
  with audio (phone speaker or headphones) as the secondary channel. The watch work is a **separate
  follow-up spec**; this spec defines the seams (`RideStatus`, `RideRemoteControl`, `AlertSink`).
- **Silent failure becomes dangerous.** With the screen out of sight, a camera that stopped
  recording looks exactly like one that is recording. Every degradation is therefore announced
  (watch haptic, audio, amber dot) and noted in the summary. This reverses the old privacy-steering
  line "camera denied: features disable themselves silently".
- **Crash-response countdown.** The approved countdown assumes a tappable phone. With a rear mount
  the cancel must also be reachable on the watch; the phone additionally exits ride mode to full
  brightness and speaks the countdown (see "Crash-response cross-reference").
- **Motion-based crash detection (crash stretch tasks 32–33) is on the bike, not the rider.** A
  seat-post mount has a different vibration signature and "drops" differently (the bike falling over
  while parked looks like a crash). That stretch work must be field-tested on a mount; the crash spec
  gets a short Risks note.

### B. "Record when the phone/screen is off" — what iOS actually allows

See the capability table. The honest summary: **iOS interrupts a third-party camera session when
the app is backgrounded or the device is locked.** The supported design is ride mode (foreground,
black, minimum brightness, touch-locked, idle timer disabled) so the phone *looks* off and draws
little display power while capture and GPS run. If the phone is locked anyway, camera recording
stops cleanly and the rider is told; GPS can continue because the `location` background mode is
enabled (O-CAM2).

### C. Camera now, model later

Capture, recording, and clips ship without a model. The detector (Teammate B) is a `FrameConsumer`
registered with the `FramePipeline`; it never owns the session, the permission, or the writer. The
`HazardDetection` value type is frozen and unchanged.

### D. Dashcam-style recording

Rolling 15 s segments in a bounded ring buffer; clips are *pinned* from it. The crash-response
`FootageBuffer` is implemented on top of the pinning path.

### E. Privacy

Footage is on-device only, excluded from backups, never uploaded, never in a crash message. Role C
gets events only. See "Privacy and network invariants".

### F. UX additions

Mount & frame, recording indicator (red dot in ride mode, chip on the ride screen), clip lists in
summary/history.

### G. Team split

See `../../team/team-plan.md` (updated) and "Risks" below.

---

## iOS capability investigation

**Method and honesty note.** On October 24, 2026 the Apple pages marked **Checked** were fetched
from `developer.apple.com` (their Markdown versions). The fetch dropped some inline code words
(for example the Info.plist key names inside sentences), so semantics were confirmed from
context and the surrounding API names. Items tagged **Verify** MUST be confirmed on device or in
current docs before a task relies on them. Nothing here is a promise about behavior on a specific
OS release.

| # | Question | Finding | Status |
| - | -------- | ------- | ------ |
| 1 | Can an iPhone app keep an `AVCaptureSession` running in the background or when locked? | **No.** The capture session is interrupted when the app is sent to the background; `AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground` ("an interruption caused by the app being sent to the background while using a camera") exists for exactly this. Whoosh designs for the interruption rather than around it. | **Checked** (Apple: AVCaptureSession.InterruptionReason) |
| 2 | Does the multitasking camera access entitlement change that? | **No.** `com.apple.developer.avfoundation.multitasking-camera-access` lets an app keep using the camera while **another app is also in the foreground** (Slide Over, Split View, Picture in Picture), and Apple states its usage "is restricted to apps that use `voip` as one of their" background modes. `AVCaptureSession.isMultitaskingCameraAccessSupported` is `true` on an iPad with Stage Manager and an extended display, for apps linked against iOS 18+ that declare `voip`, or for apps with the entitlement; the matching interruption reason (`...WithMultipleForegroundApps`) is described as "running in Slide Over, Split View, or Picture in Picture mode on iPad". None of this covers a locked or backgrounded iPhone. **Not relied on.** | **Checked** (Apple: entitlement page, `isMultitaskingCameraAccessSupported`, `isMultitaskingCameraAccessEnabled`, `InterruptionReason`) |
| 3 | Can the app keep running to *do other things* (GPS) when locked? | Yes with the `location` background mode: Apple documents that apps receiving location updates in the background must declare `UIBackgroundModes` with `location` and set `allowsBackgroundLocationUpdates`; setting it **without** the key is a **fatal error**; when set and updates were started in the foreground, Core Location keeps the app running and arranges the **background location indicator**, "extending the effectiveness of `authorizedWhenInUse`". So **When-In-Use + background mode + the flag + indicator** works without an Always prompt. | **Checked** (Apple: `allowsBackgroundLocationUpdates`); device behavior **Verify** |
| 4 | Alternative to the flag in iOS 17 | `CLBackgroundActivitySession` is the newer way to sustain background location from the foreground; either satisfies the design. Choose whichever behaves on the iPhone 14 test (task 24). | **Verify** |
| 5 | Idle timer and brightness | `UIApplication.isIdleTimerDisabled` keeps the screen on (the MVP's `ActiveRideView` already sets it). Screen brightness is settable through the screen of the active window scene (the global `UIScreen.main` accessor is deprecated). Whether iOS restores a changed brightness when the app is backgrounded or quits, and whether Auto-Brightness fights the setting, is **not** assumed: the design records the original, restores on every exit path, re-applies if the system overrides, and persists a launch-time guard. | **Verify on device** |
| 6 | Asset writer capabilities | `AVAssetWriter` writes HEVC or H.264 MP4/MOV from sample buffers with `expectsMediaDataInRealTime`; `movieFragmentInterval` produces fragmented files that stay playable if the process dies; a new writer per segment starts with a keyframe. HLS-style segment callbacks (`preferredOutputSegmentInterval` + delegate) exist but produce fragmented-MP4 chunks the app would have to stitch, so the design uses **one writer per segment**. | Established API; fragment recovery **Verify** |
| 7 | Frame access | `AVCaptureVideoDataOutput` delivers `CMSampleBuffer`s on a delegate queue; `alwaysDiscardsLateVideoFrames = true` makes late frames drop instead of queuing; the output's buffer pool is small, so holding buffers starves capture. | Established |
| 8 | Thermal and pressure signals | `ProcessInfo.thermalState` (nominal/fair/serious/critical) and `AVCaptureDevice.systemPressureState` (level plus factors such as system temperature and peak power) with `AVCaptureSession.InterruptionReason.videoDeviceNotAvailableDueToSystemPressure` for forced stops. Frame-rate changes can be applied live; **resolution** changes require reconfiguration (a brief gap), so they are done at segment boundaries. | Established; pressure-level thresholds **Verify** |
| 9 | Stabilization and exposure | `preferredVideoStabilizationMode`, `activeMaxExposureDuration`, far-range continuous autofocus (`autoFocusRangeRestriction`) are device-format dependent; apply only when supported. Stabilization may crop the field of view. | **Verify** per format on iPhone 14 |
| 10 | Notification mirroring to Apple Watch | iOS mirrors notifications to the watch only when the **iPhone is locked or the screen is off**. In ride mode the iPhone screen is **on**, so mirrored notifications would not reach the wrist; a direct WatchConnectivity channel is required for live alerts. When the phone *is* locked (camera paused), the "camera paused" notification does mirror. | **Verify** |
| 11 | WatchConnectivity during a ride | `sendMessage` needs the counterpart reachable (typically the watch app active); continuous use is realistic only if the watch app keeps itself alive, for example with a cycling `HKWorkoutSession`. Latency and battery are watch-spec concerns. Fallbacks (`updateApplicationContext`, `transferUserInfo`) are not suitable for urgent alerts. | **Verify** (watch spec) |
| 12 | Free-space query | `URLResourceValues.volumeAvailableCapacityForImportantUsage` reports space usable for important data (more realistic than raw available capacity). | **Verify** |
| 13 | File protection and backup exclusion | Segment files need a protection class that allows writing after the first unlock even when the device is locked (for example `completeUntilFirstUserAuthentication`), and `isExcludedFromBackup` on the camera directories. | **Verify** |
| 14 | Hard links | `FileManager.linkItem` creates APFS hard links, used to pin without copying; copying is the fallback if linking fails. | Established; **Verify** on device |
| 15 | Photos export | Add-only authorization (`NSPhotoLibraryAddUsageDescription`) lets the app save a video without reading the library. A system share sheet "Save Video" would avoid any permission and is the alternative recorded in D-CAM15. | **Verify** |
| 16 | Operating temperature | Apple documents an operating ambient range of roughly 0–35 °C for iPhone; a dark phone in sun on a seat post can exceed the device's comfortable range regardless of ambient air. Heat is a first-class risk. | **Verify** (current Apple environmental specs for the model) |
| 17 | Guided Access | A rider can start Guided Access (triple-click) to disable the side button and touch, which also prevents an accidental lock. An app cannot start it for ordinary users. Offered as a tip only. | **Verify** |
| 18 | Bluetooth handlebar shutter remote | A Bluetooth camera-shutter remote can act as a volume-button event source; apps can observe hardware button events while the camera is in use (`AVCaptureEventInteraction`). A candidate low-cost "Save clip" button on the handlebar when no watch exists. | **Verify** (Stretch task) |
| 19 | Phone calls / Focus | An incoming call that is answered, or a system takeover, interrupts the session like backgrounding. A Focus (Do Not Disturb) reduces this. The checklist reminds the rider. | Established; **Verify** |
| 20 | Swift 6 and `CVPixelBuffer` | Core Video buffers are not `Sendable`; crossing actors needs an explicit wrapper with a documented immutability contract. | **Verify** with the Xcode 26.5 toolchain |

---

## Rear-mount consequences — summary table

| Area | MVP assumption | Rear-mount design |
| ---- | -------------- | ----------------- |
| Starting a ride | Tap Start on the active screen | Start on phone after Mount & frame; mount grace; ride mode |
| Pause / resume | Tap on phone | Watch command (or unlock gesture on phone) |
| Stop | Press-and-hold on phone | Watch hold, or unlock gesture then hold-to-stop on phone |
| Live numbers | Three numbers on the screen | Watch complication/app; phone screen is black |
| Alerts | Phone haptic/audio (stub) | Watch haptic first, audio second (`AlertSink` fan-out) |
| Camera health | Not applicable | Always announced; red dot / amber dot; watch |
| Brightness / OLED | Screen on, bright | True black, minimum brightness, touch-locked |
| Crash countdown cancel | Tap on phone | Watch cancel + audible phone countdown + on-screen cancel |

---

## Architecture and layering

### Layering additions

| Layer / folder | Contents | Knows about | Must NOT import |
| -------------- | -------- | ----------- | --------------- |
| `Models/` | `CaptureProfile`, `CameraRecordingState`, `CameraStopReason`, `InterruptionReasonKind`, `SegmentInfo`, `ClipRecord`, `ClipReason`, `ClipState`, `PinRequest`, `PinWindow`, `NearMissEvent`, `RideCameraTuning`, `ScreenMode`, `ThermalLevel`, `StorageStatus`, `RideStatus`, `RideRemoteCommand`, `CameraPermissionStatus`; additions to `AlertKind` | Foundation | everything else |
| `Metrics/` (Foundation-only, pure) | `RingBufferPolicy`, `ClipWindowPolicy`, `ClipCoalescing`, `ThermalPolicy`, `StoragePolicy`, `BatteryPolicy`, `CaptureProfileSelector`, `FrameDropPolicy`, `CameraStateMachine` (reducer), `ScreenModeStateMachine` (reducer), `BrightnessGuard`, `LevelCalculator`, `ReadinessEvaluator`, `NearMissPolicy`, `AlertRoutingPolicy`, `NearMissUploadMapper`, `StatusThrottle` | Models | UI, any framework |
| `Services/Camera/` | `CameraPermission` (protocol + AV impl + fake), `CameraCapturing` (protocol), `CameraCaptureService` (the only `AVCaptureSession` owner), `FakeCameraSource`, `FileFrameSource` (stretch), `VideoFrame`, `FrameConsumer`, `FramePipeline`, `SegmentRecording` + `AssetWriterSegmentRecorder` + fake, `SegmentStore` + `FileSegmentStore` + in-memory fake, `ClipPinner`, `ClipFootageBuffer`, `ClipThumbnailer`, `ClipPlayback` (composition builder), `ClipExporting` + `PhotosClipExporter` (the only Photos file), `MountLevelSensor` (Core Motion), `CameraPreviewHost` (UIKit view that attaches to the session) | Models, Metrics | SwiftUI, other services' concrete types |
| `Services/Screen/` | `ScreenController` protocol, `UIKitScreenController` (brightness, idle timer; the only code touching them), `FakeScreenController`, `DimGuardStore` (persists the brightness guard) | Models, Metrics | SwiftUI |
| `Services/Remote/` | `RideRemoteControlling` protocol, `NoopRideRemote`, `FakeRideRemote`; the WatchConnectivity implementation arrives with the watch spec (the only place `WatchConnectivity` may be imported) | Models | SwiftUI |
| `Services/Alerts/` | adds `AlertSink` protocol, `FanOutAlertManager` (an `AlertManager`), `PhoneAudioAlertSink`, `LocalNotificationAlertSink`, `FakeAlertSink`; the existing `AlertManager` protocol and `StubAlertManager` stay | Models, Metrics | SwiftUI |
| `Services/Persistence/` | adds `ClipRepository` protocol, `SwiftDataClipRepository`, `InMemoryClipRepository`, `ClipRecordEntity` (`@Model`), near-miss storage | Models | SwiftUI |
| `Services/Detection/` | unchanged seam types; doc contract updated (see "HazardDetector seam update"); `DetectionCoordinator` | Models, Metrics, Camera protocols | capture APIs |
| `Features/Camera/` | `MountAndFrameView(+VM)`, `RideModeView`, `RideModeController` (`@Observable`), `ClipListView`, `ClipPlayerView`, `RearCameraSettingsSection`, `CameraRecordingCoordinator` (`@Observable`), `RideCameraBridge` | ViewModels, Theme | AVFoundation, UIKit screen APIs, concrete services |
| `Support/Representables/` | `CameraPreviewView` (wraps the service-provided preview host), `VideoPlayerView` (AVKit playback) | UIKit/AVKit | capture session, writer |
| `App/` | composition-root additions in `AppEnvironment`; ride-mode overlay host in `WhooshApp`'s ride cover | everything | — |

### File layout (proposed)

```
Whoosh/
  Models/        CaptureProfile · CameraRecordingState · ClipRecord · NearMissEvent · RideCameraTuning · RideStatus …
  Metrics/       RingBufferPolicy · ClipWindowPolicy · ThermalPolicy · StoragePolicy · FrameDropPolicy · CameraStateMachine ·
                 ScreenModeStateMachine · BrightnessGuard · LevelCalculator · ReadinessEvaluator · NearMissPolicy · AlertRoutingPolicy …
  Services/
    Camera/      CameraCapturing · CameraCaptureService · FramePipeline · FrameConsumer · VideoFrame · SegmentRecording · SegmentStore ·
                 ClipPinner · ClipFootageBuffer · PhotosClipExporter · MountLevelSensor · fakes
    Screen/      ScreenController · UIKitScreenController · FakeScreenController · DimGuardStore
    Remote/      RideRemoteControlling · Noop · Fake
    Alerts/      (existing) + AlertSink · FanOutAlertManager · sinks
    Persistence/ (existing) + ClipRepository · SwiftData · InMemory
    Detection/   (existing) + DetectionCoordinator
  Features/
    Camera/      Mount & frame, ride mode, clip list/player, coordinator, bridge
  Support/Representables/  CameraPreviewView · VideoPlayerView
WhooshTests/     Fakes and tests for every pure policy and state machine in this document
```

Dependency rule: identical to the MVP. Views → view models → service **protocols**; concrete types
are injected at the composition root.

### On-disk layout

```
Application Support/Whoosh/Camera/        (isExcludedFromBackup; protection: after first unlock)
  ring/<rideID>/seg-<index>-<startEpochMs>.mp4     unpinned segments (bounded)
  clips/<clipID>/seg-….mp4  thumb.jpg              pinned (hard links, copy fallback)
  tmp/                                             Mount & frame test recording, export staging (deleted promptly)
```

---

## Domain models (described, not coded)

### RideCameraTuning (all constants in one place; defaults are *(verify)* hypotheses)

| Constant | Default | Range / note |
| -------- | ------- | ------------ |
| Segment length | 15 s | 10–30 s |
| Movie fragment interval | 2 s | segment-internal recoverability |
| Key-frame interval | 1 s | quick cuts, clean segment starts |
| Ring max duration | 10 min | 2–30 min (Settings "Buffer length") |
| Ring max bytes | 1 GB | 256 MB–4 GB |
| Pinned (clips) max bytes | 2 GB | |
| Standard profile | 1080p, 30 fps, HEVC, 5 Mbps average | H.264 at ~1.6× bitrate if HEVC unsupported |
| Efficient profile | 720p, 30 fps, HEVC, 2.5 Mbps | default in Low Power Mode |
| Reduced profile | 720p, 15 fps, HEVC, 1.2 Mbps | thermal/battery step |
| Manual pin pre/post | 30 s / 15 s | |
| Detection pin pre/post | 15 s / 10 s | |
| Crash pin pre/post | 60 s / 30 s | |
| Coalesce gap | 5 s | windows overlapping or this close merge |
| Max clip duration | 180 s | merged cap |
| Auto-pin cooldown | 20 s | |
| Max auto-pins per ride | 10 | |
| Manual-save debounce | 2 s | |
| Free space: start / warn / stop | 2 GB / 1 GB / 500 MB | |
| Battery: suggest-efficient / stop floor | ≤ 20% / ≤ 8% (not charging) | |
| Thermal step-up hysteresis | ≥ 5 min at fair or better; ≤ 1 step-up / 10 min | |
| Interrupted notice threshold | 5 s | before alerting |
| Resume attempts after interruption | 3 within 30 s | then wait for foreground |
| Mount grace | 20 s | 5–60 s |
| Unlock gesture | two fingers, 1.0 s hold | |
| Unlock window (inactivity) | 10 s | then re-dim |
| Dim brightness | minimum (0.0) | |
| Red-dot shift period | 60 s, a few points | display protection |
| Clip retention | 30 days | O-CAM4 |
| Test recording | 10 s | Mount & frame |
| Analysis frame rate (consumers) | consumer-declared (expected ≤ 10 fps) | |
| Background-task finalize budget | ≤ 3 s | segment finalize on interruption |
| Camera restart after writer failure | once after 2 s | |

### Entities

| Entity | Fields (summary) | Storage |
| ------ | ---------------- | ------- |
| `CaptureProfile` | name, width, height, fps, codec, average bitrate | constants |
| `SegmentInfo` | id, rideId, index, start (Date), end (Date), bytes, profile name, hasAudio, isPinned, hasGapBefore | in-memory index rebuilt from files on launch |
| `ClipRecord` | id, rideId, reasons (set of `manual`, `detection`, `crash`, `demo`), createdAt, start, end, inOffset, outOffset, duration, bytes, thumbnail path, hasAudio, state (`pending`/`saved`/`endedEarly`), hasGap, eventRef (nearMissId or crashEventId), expiresAt | SwiftData `ClipRecordEntity` behind `ClipRepository` |
| `NearMissEvent` | id, rideId, occurredAt, latitude, longitude (nearest accepted route point, may be absent), kind, confidence, positionHint, localClipId? | SwiftData via the same repository family; clip id is **local only** |
| `RideStatus` | rideState, activeDurationAnchor (+ anchor date), distanceMeters, speed?, cameraState, cameraStopReason?, storageStatus, thermalLevel, phoneBatteryPercent, isCharging, banner, crashCountdownDeadline?, lastClipSavedAt?, lastDegradationNote? | value snapshot, never persisted |
| `RideRemoteCommand` | pause · resume · saveClip · stop(confirmedByHold) · cancelCrashCountdown | transient |
| `ScreenMode` | normal · graceCountdown(until) · dimLocked · unlockedTemporarily(until) · suspended | in-memory (+ persisted brightness guard) |
| `AlertKind` (additions) | existing `cautionRearVehicle`; new `cameraInterrupted`, `cameraResumed`, `cameraStopped(reason)`, `clipSaved`, `clipNotSaved(reason)`, `phoneBatteryLow` | enum, `Sendable` |

---

## Service protocols (described, not coded)

| Protocol | Members (summary) | Implementations |
| -------- | ----------------- | --------------- |
| `CameraPermission` | `status`, `request()` async, `onChange`; microphone variant when audio is enabled | AV-backed, `FakeCameraPermission` |
| `CameraCapturing` | `start(profile, orientation, audio)`, `stop()`, `apply(profileStep)`, state/event callbacks (running, interrupted(reason), runtimeError, pressure change), `frameSink` (a `FramePipeline`), `recorder` hand-off, `makePreviewHost()` for Mount & frame; all work off-main, callbacks on main | `CameraCaptureService`, `FakeCameraCapture` |
| `FrameConsumer` | see exact specification below | Teammate B's detector; `RecordingFrameStats` test consumer |
| `SegmentRecording` | `begin(profile, orientation)`, `append(sample)`, `rotate(at)`, `finish()`, callbacks `segmentFinished(SegmentInfo)`, `failed(error)`; never blocks; drops when not ready | `AssetWriterSegmentRecorder`, `FakeSegmentRecorder` |
| `SegmentStore` | `register(segment)`, `segments(rideId)`, `delete(ids)`, `link(segment → clip)`, `bytesUsed`, `purgeOrphans()`, `freeSpace()` | `FileSegmentStore` (temp-dir tests), `InMemorySegmentStore` |
| `ClipRepository` | `save`, `clips(rideId)`, `clip(id)`, `delete(id)`, `deleteAll(rideId)`, `deleteAll()`, `expired(now)`, `totalBytes()` | SwiftData, in-memory |
| `FootageBuffer` (crash-response's protocol) | `preserve(eventId, around)` → local reference or none; `delete(reference)` | `NoopFootageBuffer` (exists in that spec), `ClipFootageBuffer`, fake |
| `ClipExporting` | `export(clip)` async → success/failure with plain reason | `PhotosClipExporter`, fake |
| `ScreenController` | `brightness`, `setBrightness`, `setIdleTimerDisabled`, `onSystemBrightnessChange` | `UIKitScreenController`, `FakeScreenController` |
| `RideRemoteControlling` | `publish(RideStatus)`, `onCommand(RideRemoteCommand, reply)`; reachability callback | `NoopRideRemote`, `FakeRideRemote`; WatchConnectivity impl (watch spec) |
| `AlertSink` | `channel`, `isAvailable`, `deliver(AlertKind, context)` non-blocking | `PhoneAudioAlertSink`, `LocalNotificationAlertSink`, watch sink (watch spec), `FakeAlertSink` |
| `AlertManager` (existing, unchanged) | `fire(AlertKind)` | `StubAlertManager`, `FanOutAlertManager` |
| `HazardDetector` (existing) | unchanged members; contract text updated | `NoopDetector`, `FakeHazardDetector`, Teammate B's detector |
| `MountLevelSensing` | gravity vector stream for the level indicator | `MountLevelSensor` (Core Motion), fake |

---

## Frame pipeline and the consumer contract (for Teammate B)

### Data flow and threads

```
 capture queue ("camera.video", serial, userInteractive/high QoS)
   AVCaptureVideoDataOutput (alwaysDiscardsLateVideoFrames = true)
        │ CMSampleBuffer
        ├─▶ SegmentRecorder.append     (same queue; if !isReadyForMoreMediaData ⇒ drop + count; rotation swaps writers)
        └─▶ FramePipeline.offer(frame)   (registry empty ⇒ return immediately)
               for each consumer c:
                  1. FrameDropPolicy.decide(frame.time, c.lastDeliveredTime, c.maxFPS)   → drop(rate) | pass
                  2. c.mailbox.replace(frame)      single slot; if occupied ⇒ older frame dropped (busy)
                  3. wake c's driver
 per-consumer driver (own task/actor, never the main actor)
        loop: take latest from mailbox → await c.consume(frame) → release frame → repeat
```

Capture and the writer are on the hot path; consumers are strictly downstream. Nothing a consumer
does can delay capture, the writer, or another consumer.

### `VideoFrame` (value passed to consumers)

| Field | Meaning |
| ----- | ------- |
| `pixelBuffer` | The image (`CVPixelBuffer`), read-only by contract; 8-bit bi-planar 4:2:0 by default |
| `presentationTime` | Monotonic capture-session time in seconds (for ordering/intervals) |
| `capturedAt` | Wall-clock `Date` of capture, derived from a host-clock anchor; **this is the value a detector copies into `HazardDetection.timestamp`**, so clip windows align with the video |
| `orientation` | How the buffer must be rotated to be upright for the mount (maps to Vision's image orientation) |
| `sequence` | Increasing integer per camera session |
| `isDiscontinuity` | True for the first frame after an interruption, restart, or format change |
| `format` | Width, height, pixel format, frame rate currently active |

`VideoFrame` is an `@unchecked Sendable` wrapper with an immutability contract (Swift 6 note,
capability row 20).

### `FrameConsumer` — exact contract

| Member | Meaning |
| ------ | ------- |
| `consumerID` | Stable string for registration/diagnostics |
| `configuration` | `maxFramesPerSecond` (the pipeline never delivers faster), `preferredPixelFormat`, `maxDimensionHint` (a request, honored when cheap), `wantsDiscontinuityReset` |
| `consume(frame)` (async) | Called off the main actor, one frame at a time. Return when done with the frame. Must not retain the frame after returning (copy if history is needed). May take longer than the frame interval; the pipeline will simply drop newer frames. |
| `pipelineDidStart(format)` / `pipelineDidStop()` | Lifecycle notifications; delivered off-main |
| error behavior | `consume` does not throw into the pipeline; a consumer handles its own failures. A consumer that is repeatedly slow is not removed; it is reported in stats. |

### Backpressure rule (normative)

1. Each consumer has exactly **one pending slot** (latest wins). A newer frame replaces the pending
   one, and the replaced frame is counted as a busy-drop.
2. The pipeline **never awaits** a consumer, never queues more than one pending frame per consumer,
   and never retains more than `1 in-flight + 1 pending` buffers per consumer.
3. The segment writer is fed independently of all consumers; if the writer is not ready, the frame
   is dropped for the writer only.
4. Rate limiting happens *before* the mailbox: frames above `maxFramesPerSecond` are rate-dropped
   (with jitter tolerance: a frame arriving at ≥ 90% of the interval is passed).
5. Stats per consumer: offered, delivered, rate-dropped, busy-dropped; exposed to a diagnostic view
   and to tests.
6. Registration/removal is safe at any time; a newly registered consumer receives frames from the next
   one, flagged as a discontinuity.

### `FrameDropPolicy` (pure; test-first)

| Case | Inputs | Output |
| ---- | ------ | ------ |
| First frame for a consumer | no last delivered | pass |
| On-rate | Δt ≥ 0.9 × (1 / maxFPS) | pass |
| Too soon | Δt < 0.9 × interval | drop(rate) |
| Clock jump backward | Δt < 0 | pass, reset baseline |
| Large gap | Δt > 1 s | pass, flag discontinuity to consumer |
| Consumer busy | pending occupied | replace pending; count busy-drop |
| maxFPS ≥ capture fps | — | pass every frame |
| maxFPS = 0 or invalid | — | clamp to 1 fps |

### Perf expectations for consumers *(verify)*

Analysis at ≤ 10 fps on a downscaled buffer; inference time target ≤ 100 ms so it keeps pace;
slower is allowed (frames drop). Detector CPU/GPU/ANE load counts toward thermal and battery
budgets, so the thermal policy can also **lower the delivered rate to consumers** (`serious` ⇒
consumers capped at half rate) before reducing recording quality.

---

## HazardDetector seam update (design-level; the code change is a task)

| Aspect | Before (MVP) | After |
| ------ | ------------ | ----- |
| Frame input | none; the seam had no input | A camera-based detector **is a `FrameConsumer`** (it conforms to both `HazardDetector` and `FrameConsumer`). The composition root / `DetectionCoordinator` registers it with the `FramePipeline`. |
| Capture ownership | unspecified ("camera") | Detectors **never** create an `AVCaptureSession`, never request camera permission, and never write video. `CameraCaptureService` and `CameraPermission` own those. The privacy-check no longer allows capture APIs in `Services/Detection`. |
| `start()` / `stop()` | begin/stop detection | `start()` registers the consumer and begins inference; `stop()` unregisters and releases model resources. Still non-blocking. |
| `onDetection` | main-actor callback | unchanged. `HazardDetection.timestamp` SHOULD be the triggering frame's `capturedAt` (not inference-completion time). |
| `HazardDetection` shape | `timestamp`, `kind`, `confidence`, `relativePositionHint` | **Unchanged** (frozen contract). |
| When it runs | n/a | Only while the camera state is `recording` or `degraded` and rear detection is enabled; paused automatically on interruption (frames stop; discontinuity flag on resume). |
| What happens with a detection | nothing | `DetectionCoordinator` → `NearMissPolicy` → (a) local `NearMissEvent`, (b) clip pin (if enabled), (c) `AlertManager.fire(.cautionRearVehicle)` after the existing debounce/cooldown. |
| `NoopDetector` doc | "no camera permission anywhere in the MVP" | Updated: the no-op never registers a consumer; camera permission belongs to rear camera recording, not to detection. |
| Detect-only (no recording) | n/a | Out of scope for v1 (`FUTURE`): the camera session runs only with recording on. |

Teammate B can start against `FrameConsumer`, `VideoFrame`, `FakeCameraSource` (synthetic frames)
and `FileFrameSource` (replay a recorded clip at real time) **before** the capture service exists.
The consumer contract is frozen with a 3-way OK (iOS, B, C) like `HazardDetection`.

---

## Recording model

### Segment recorder

- One `AVAssetWriter` per segment, HEVC (H.264 fallback), video input with
  `expectsMediaDataInRealTime`, average bitrate from the profile, key frames every 1 s, movie
  fragments every 2 s, orientation transform from the mount orientation.
- Rotation: when a frame's presentation time passes the segment boundary, the recorder starts the
  next writer on that very frame (so segment *n+1* begins with a keyframe) and finishes writer *n*
  asynchronously. The gap is at most one frame interval; nothing waits on `finishWriting`.
- Each finished segment is registered with `SegmentStore` (start/end wall-clock, bytes, profile).
- Writer back-pressure: `isReadyForMoreMediaData == false` ⇒ drop the frame and count it. A writer
  error discards that segment and triggers the camera reducer's `writerFailed` event.
- Audio (stretch): a second input fed by an audio data output on its own queue; a missing or
  denied microphone means video-only.

### Ring buffer and `RingBufferPolicy` (pure; test-first)

Inputs: the segment list (id, end time, bytes, isPinned, isOpen, inPendingWindow), `now`, max duration,
max bytes (after the storage guard's effective cap). Output: the ordered list of segment ids to
delete.

| Rule | Behavior |
| ---- | -------- |
| Eligibility | Never the open segment, never a pinned segment, never one in a pending post-roll window |
| Bounds | Evict while (unpinned span > max duration) **or** (unpinned bytes > max bytes) |
| Order | Oldest end time first; ties by lower index |
| Exactly at bound | Not evicted (strictly greater triggers) |
| Eligible set empty but over bound | Evict nothing (report `overBoundUnevictable`); the storage guard decides |
| Effective cap shrink | When `StoragePolicy` reduces the cap, the same function evicts down to it |
| Empty / single segment | No-op |
| Out-of-order registration | Sort by end time before deciding |

### Pinning and `ClipWindowPolicy` (pure; test-first)

Inputs: event time, source (manual/detection/crash), tuning pre/post, the available segment index,
`now`, existing clips (for coalescing), ride bounds. Output: a `PinWindow` — segment ids to keep, precise
in/out offsets, `pendingUntil` (event time + post-roll, if in the future), flags (`hasGap`, `truncatedAtRideStart`).

| Case | Behavior |
| ---- | -------- |
| Normal | Window = [t − pre, t + post]; snap outward to segment boundaries for the keep-set; keep exact offsets for playback/export |
| Near ride start (less than `pre` available) | Clamp to the earliest segment; `truncatedAtRideStart` |
| Post-roll in the future | `pendingUntil` set; segments added as they finish; covering segments protected |
| Ride ends before post-roll completes | Finalize with what exists; state `endedEarly` |
| Gap inside the window (interruption) | Keep existing segments only; `hasGap` |
| No segments in the window | No clip; "nothing to save" |
| Coalescing | Existing clip overlapping or within `coalesceGap` ⇒ merge into the union, up to `maxClipDuration`; beyond the cap start a new clip (a shared boundary segment is linked into both) |
| Clip storage cap reached | Manual: allowed only if the cap leaves room, else "Storage full for clips"; auto-pins: refused |
| Cooldown / per-ride cap / debounce | Applied by `NearMissPolicy` and the manual debouncer, not here |

Pin mechanics: hard-link each segment into `clips/<clipID>/` (copy if linking fails), mark it pinned in
the index (no longer counted toward ring bounds), then remove the ring path. The clip record is
written `pending` and flips to `saved`/`endedEarly` when the post-roll completes. Pinning runs on a
background task and never touches the capture queue.

### Clip playback, thumbnails, export

- Playback builds an `AVComposition` of the clip's segments trimmed to in/out and plays it with the
  standard AVKit controls (`VideoPlayerView`).
- Thumbnail: a single image at the event instant (320 px), generated after the clip is `saved`.
- Export (explicit, per clip): build a single MP4 via the passthrough export preset into `tmp/`, hand
  it to `PhotosClipExporter` (add-only authorization requested at that moment), delete the temp file.
  The clip is never moved. The share-sheet alternative is recorded in D-CAM15.
- Retention: a launch- and foreground-time sweep deletes expired clips (`expiresAt`).

### Camera recording state machine (pure reducer; every row a unit test)

States: `off`, `preparing`, `recording(profile)`, `degraded(profile, reason)`, `interrupted(reason)`,
`stopped(reason)` (stopped by policy: thermal, storage, battery, permission), `stopping`,
`failed(reason)`.

| # | From | Event | Guard | To | Effects |
| - | ---- | ----- | ----- | -- | ------- |
| 1 | off | ride started (feature on) | permission authorized ∧ storage ≥ start min ∧ profile resolved | preparing | start session, open first segment |
| 2 | off | ride started | permission not authorized | off | alert `cameraNotStarted(permission)`; banner |
| 3 | off | ride started | storage < start min | off | alert `cameraNotStarted(storage)`; banner |
| 4 | preparing | session running | — | recording | publish status; schedule thermal/storage polling |
| 5 | preparing | runtime error / 5 s timeout | attempts < 2 | preparing | retry after 2 s |
| 6 | preparing | runtime error / timeout | attempts exhausted | failed | alert `cameraStopped(failed)` |
| 7 | recording | thermal step down | — | degraded | lower fps live or resolution at boundary; alert `cameraStopped`-class notice "reduced" |
| 8 | degraded | thermal step up | hysteresis satisfied | recording or degraded (higher) | restore profile at boundary |
| 9 | recording, degraded | session interrupted(reason) | — | interrupted | finalize segment (background task); record gap; notice after 5 s |
| 10 | interrupted | interruption ended | ride active | preparing | new segment; discontinuity flag; attempts counted |
| 11 | interrupted | interruption ended | ride not active | off | teardown |
| 12 | recording, degraded | thermal critical / system-pressure stop | — | stopped(thermal) | finalize; GPS unaffected; alert |
| 13 | recording, degraded | storage < stop floor | — | stopped(storage) | finalize; alert; auto-pins refused |
| 14 | recording, degraded | battery ≤ floor ∧ not charging | — | stopped(battery) | finalize; alert |
| 15 | stopped(thermal) | cooldown satisfied | ride active | preparing | resume at reduced profile |
| 16 | stopped(storage) | free space ≥ start min | ride active | preparing | resume |
| 17 | stopped(battery) | charging or battery above floor + margin | ride active | preparing | resume |
| 18 | any camera-active | permission revoked | — | stopped(permission) | finalize; alert |
| 19 | recording, degraded | writer failed | restart not yet tried | preparing | discard bad segment; restart once |
| 20 | recording, degraded | writer failed | restart tried | failed | alert |
| 21 | any | ride ended / feature disabled | — | stopping → off | finalize, finish pending pins, delete unpinned segments, teardown session |
| 22 | failed | retry timer (60 s, max 3) | ride active | preparing | try again |
| 23 | any | ride paused / resumed | — | same | the camera keeps recording through a pause (`recordWhilePaused`, default on) |
| 24 | any | undefined event | — | same | no-op |

---

## Ride mode (screen-dim mode)

### Behavior

| Element | Specification |
| ------- | ------------- |
| Entry | After Start with ride mode on: a **mount grace** screen (20 s countdown, "Dim now", "Keep screen on"), then `dimLocked` |
| Presentation | An overlay above the active-ride content inside the existing non-dismissible ride cover: solid black, status bar hidden, home indicator auto-hidden, nothing else but the red dot (and transient toasts / an amber dot) |
| Brightness | Record the original; set to minimum; restore on exit, ride end, resign-active, and next launch (guard); if the system changes brightness (Auto-Brightness) re-apply, ignoring our own changes |
| Idle timer | Disabled while the overlay is active (the screen controller owns the call; `ActiveRideView`'s direct call moves behind it in a task) |
| Touch lock | A full-screen touch-absorbing layer; the only recognized gesture is the **two-finger long press (1.0 s)**; every other touch is ignored |
| Unlock | Restores the original brightness, shows the Pause/Resume, Save clip, and hold-to-stop controls (60 pt targets); after 10 s of inactivity re-dims and re-locks |
| Recording dot | A small red circle plus (for VoiceOver) an accessibility label "Recording"; shifts a few points every 60 s; never hidden; no attempt to hide or imitate system camera/location indicators |
| Trouble | Camera interrupted/stopped/failed or GPS signal lost: the red dot becomes an **amber dot** (shape differs: ring) |
| Toasts | "Clip saved" / "Couldn't save clip" for 2 s, very dim |
| Accessibility | One element "Ride mode. Camera recording. Unlock." with a custom action **Unlock controls**; announcements for camera state changes |
| Optional | Ride mode can be turned off; the existing active-ride screen is then used |
| Stretch | `pickedUp` event (large orientation change away from the mount while slow) auto-unlocks |

### `ScreenModeStateMachine` (pure reducer; every row a unit test)

| # | From | Event | Guard | To | Effects |
| - | ---- | ----- | ----- | -- | ------- |
| 1 | normal | ride started, ride mode on, camera feature on | — | graceCountdown(now+20 s) | idle timer off; show grace UI |
| 2 | graceCountdown | "Dim now" / grace elapsed | — | dimLocked | store original brightness; persist dim guard; set min brightness; touch lock on |
| 3 | graceCountdown | "Keep screen on" | — | normal (ride mode off for this ride) | idle timer stays off |
| 4 | dimLocked | two-finger hold completed | — | unlockedTemporarily(now+10 s) | restore brightness; touch lock off; show controls |
| 5 | dimLocked | accessibility "Unlock controls" | — | unlockedTemporarily | as row 4 |
| 6 | unlockedTemporarily | touch activity | — | unlockedTemporarily(extend) | extend deadline |
| 7 | unlockedTemporarily | unlock deadline reached | — | dimLocked | re-apply dim and lock |
| 8 | dimLocked, unlockedTemporarily, graceCountdown | app resigns active | — | suspended | restore brightness; clear guard |
| 9 | suspended | app becomes active | ride active ∧ ride mode on | unlockedTemporarily(now+10 s) | idle timer off; rider sees state, then re-dims |
| 10 | any | crash countdown started | — | normal (forced) | full brightness, unlock, suppress re-dim until the countdown ends |
| 11 | normal (forced by crash) | crash countdown ended | ride active ∧ ride mode on | unlockedTemporarily | then re-dim |
| 12 | any | ride ended | — | normal | restore brightness; clear guard; idle timer per screen |
| 13 | any | system brightness changed externally | dimLocked ∧ differs from our value | dimLocked | re-apply minimum (rate-limited); if the rider changed it deliberately while unlocked, leave it |
| 14 | any | launch with an active dim guard | no ride active | normal | restore the persisted original; clear guard |
| 15 | any | undefined | — | same | no-op |

`BrightnessGuard` (pure) decides the restore target given: original, our last-set value, the current
reading, and whether the change was ours. Cases: normal restore, rider changed brightness while
unlocked (leave it), brightness already equals original (no-op), guard persisted from a previous run
(restore once), repeated enter without exit (do not overwrite the original with the dimmed value).

---

## Mount & frame

### Layout

| Region | Content |
| ------ | ------- |
| Preview | Live back-camera preview at the chosen profile, with a framing guide (horizon target in the upper third; "road behind you should fill the lower two thirds") |
| Level | Roll and pitch readout and a bubble; green/amber state with icon + text. Pure `LevelCalculator` over the gravity vector and the mount orientation. Starting targets: |roll| ≤ 3°, pitch (camera tilt) −5° to +15° (positive = down) — tuned in the field |
| Test recording | "Record 10-second test" → playback; shows file written ✓, size, measured bitrate, dropped frames |
| Checklist | Pure `ReadinessEvaluator` rows (below) |
| Choices | Profile (Standard / Efficient), mount orientation (auto from gravity, confirm), ride mode on/off |
| Actions | "Start ride" (primary, thumb zone), "Start without framing" after the first successful framing, "Done" |

### Readiness checklist (`ReadinessEvaluator`, pure; test-first)

| Row | Pass | Warn | Block |
| --- | ---- | ---- | ----- |
| Camera permission | authorized | notDetermined (will ask) | denied/restricted (shows Settings path) |
| Storage free | ≥ 2 GB | 1–2 GB | < 1 GB for starting (message: free space or choose Efficient; below the start minimum recording will not start) |
| Battery | ≥ 40% or charging | 20–40% | < 20% and not charging (suggest Efficient / power bank) |
| Low Power Mode | off | on (profile switches to Efficient; frame rate may be limited) | — |
| Thermal | nominal | fair | serious/critical |
| Location permission | While Using | not determined | denied (ride GPS impossible) |
| Dark scene | normal exposure | dark (hint) | — |
| Level | within targets | slightly off | — |
| Lens | reminder (always shown) | | |
| Secure mount | reminder (always shown) | | |
| Focus / Do Not Disturb | reminder (always shown; calls can interrupt the camera) | | |
| Guided Access tip | optional tip to prevent an accidental lock | | |

Block means: recording cannot start. Warn never blocks. The ride can always start without the
camera (a clear "Ride without camera" choice).

---

## Background reality, interruption handling, and the background location decision

### What happens when the phone locks or the app is backgrounded anyway

1. The app is told it is leaving the foreground (scene inactive / resign active). Ride mode goes to
   `suspended` and brightness is restored.
2. The system interrupts the capture session (`videoDeviceNotAvailableInBackground`). The recorder
   finalizes the open segment inside a short background task (target ≤ 3 s) so the file is
   playable; the camera reducer enters `interrupted(background)` and records the gap.
3. If the interruption lasts more than 5 s the rider is told: a **local notification** ("Camera
   paused — Whoosh can't record while the phone is locked. Open Whoosh to resume.") — which, because
   the phone is now locked, mirrors to the watch — and a watch haptic via the remote seam when
   reachable.
4. GPS continues when the `location` mode is enabled (below); the MVP snapshot safeguard persists
   in-progress ride data as before.
5. Returning to the foreground: `interrupted → preparing` with a new segment and a discontinuity
   flag; the rider sees the unlocked controls for 10 s, then ride mode re-dims.
6. Pin windows that straddle the gap contain only existing segments and are marked `hasGap`.

### Background location decision (O-CAM2 — recommend: enable now)

| Option | Behavior | Pros | Cons |
| ------ | -------- | ---- | ---- |
| (a) Foreground only (MVP, current) | GPS stops being delivered when the app is not active | No new capability | A bumped side button or a call ends GPS recording for the rest of the ride — the worst failure for the app's core value |
| **(b) `location` background mode + When-In-Use + `allowsBackgroundLocationUpdates` + indicator (recommended)** | GPS continues while locked; blue indicator shown; no Always prompt | Fixes the dominant failure; standard fitness-app justification; no new permission string (`NSLocationAlwaysAndWhenInUseUsageDescription` not required for this) | Adds the background-mode entitlement and App Review justification; slightly more battery (GPS is already running); must set the flag only while a ride is active, started from the foreground |
| (c) `CLBackgroundActivitySession` (iOS 17) | Equivalent sustaining from the foreground | Newer API | Verify behavior; pick (b) or (c) on the device test |
| (d) Always authorization | Allows starting updates from the background | Not needed | Extra prompt and review cost for no benefit here |

**Updated reasoning versus the MVP and crash-response.** The MVP chose foreground-only because
the demo path was screen-on and App Review risk had no payoff. A rear-mounted phone is *more* likely
to lock (bumps, calls, a rider fumbling with a mount), and losing the route is unacceptable, so the
payoff changed. For crash-response **O1(b)**, the objections to background location were Always
authorization, battery, review cost, and "not in the demo path"; this spec pays most of them
(When-In-Use is enough; GPS is already running; the capability is justified by ride recording).
Crash-response v1 behavior stays **(a)+(c)** as approved (the countdown logic is not changed by this
spec), but the owner may now reopen the (b) option cheaply (crash task 35). A short note is recorded
in that spec's Risks table.

**What does not change:** camera recording still cannot run while locked; ride mode remains the way
the phone "looks off".

Implementation notes (task 24): declare `UIBackgroundModes: location` in `project.yml`; extend the
location service additively (a way to request background updates, set only while a ride is active);
set the indicator on; unit-test the additive protocol surface with `FakeLocationTracker`; verify on
device with the screen locked for 10+ minutes; update `CoreLocationTracker`'s "No background modes"
doc comment.

---

## Thermal, battery, and storage budgets

### Policies (pure, test-first)

**`ThermalPolicy`** — inputs: `ProcessInfo` thermal level, capture system-pressure level, current
profile step, requested profile, time since last change; output: target profile step or stop.

| Condition | Action |
| --------- | ------ |
| nominal / fair | requested profile (Standard 30 fps) |
| serious | step 1: fps 30→24 (live); step 2: fps →15; step 3: Reduced 720p at next boundary; consumers capped at half rate |
| critical / system-pressure shutdown risk | stop camera (finalize); GPS continues; alert |
| Recovery | step up one level after ≥ 5 min at fair or better, at most one step-up per 10 min; never jump two steps |
| Rider override | none in v1 (Efficient profile is the manual lever) |

**`StoragePolicy`** — free space ≥ start min ⇒ `ok`; < warn ⇒ `warn` (cap ring at 50% and refuse
auto-pins); < stop floor ⇒ `stop`; uses the important-usage capacity measure; recomputed every 30 s
and at each segment close.

**`BatteryPolicy`** — ≤ 20% unplugged ⇒ suggest Efficient (and apply it automatically if Low Power
Mode is on); ≤ 8% unplugged ⇒ stop camera so GPS can finish the ride; charging cancels both; Low
Power Mode ⇒ Efficient.

**`CaptureProfileSelector`** — requested profile ∩ supported formats ∩ thermal step ∩ battery/LPM ⇒
the profile actually used; always returns something supported or `unavailable`.

### Budgets *(hypotheses; measure on the iPhone 14 and record in "Measured results")*

| Item | Budget / estimate |
| ---- | ----------------- |
| Storage written (Standard, 5 Mbps) | ≈ 37.5 MB/min ≈ 2.25 GB/hour (ring holds only the last N minutes) |
| Storage written (Efficient, 2.5 Mbps) | ≈ 18.75 MB/min ≈ 1.1 GB/hour |
| Storage written (Reduced, 1.2 Mbps) | ≈ 9 MB/min ≈ 0.54 GB/hour |
| Ring (Standard, 10 min) | ≈ 375 MB; hard cap 1 GB |
| Clip sizes (Standard) | manual 45 s ≈ 28 MB · detection 25 s ≈ 16 MB · crash 90 s ≈ 56 MB |
| Pinned cap | 2 GB ≈ 70 manual clips |
| Free-space guard | start ≥ 2 GB · warn < 1 GB · stop < 500 MB |
| Battery (iPhone 14) | target ≤ 25%/h for Standard + GPS High + ride mode; ≤ 18%/h Efficient; compare to a GPS-only dim baseline; a bike power bank is recommended for rides over ~2 h |
| Thermal | reach `serious` rarely in 60 min at 25 °C shade; in direct 30 °C+ sun expect throttling — measure how often and when |
| Dropped frames | < 1% at the writer over 10 min at nominal |
| Camera start latency | running within 2 s of Start |
| CPU | app CPU (excluding consumers) under ~25% of one core at Standard *(verify)* |

### Measurement protocol (task 31)

Scenarios (60 min each, phone mounted, riding or on a stand with a fan-less indoor trainer for
repeatability): S0 GPS-only dim; S1 + Efficient; S2 + Standard; S3 + Standard + synthetic consumer
at 10 fps; each at ~20 °C shade and ~30 °C sun. Record battery % every 10 min, thermal state
timeline, system-pressure level, writer dropped-frame count, storage written, and Instruments CPU
samples. Results go into "Measured results" below and drive the default profile and the Efficient
auto-switch.

### Measured results

*(empty until task 31; no performance, battery, or reliability claim is made before it is filled.)*

---

## Eyes-free surfaces: `RideStatus`, `RideRemoteControl`, `AlertSink`

### Seams

| Seam | Responsibility | Notes |
| ---- | -------------- | ----- |
| `RideStatusPublisher` | Builds a `RideStatus` from the ride bridge, the camera coordinator, battery, and the crash coordinator (when present); throttles with `StatusThrottle` (on change, plus a 5 s heartbeat; the watch ticks the clock itself from an anchor) | Pure throttle; read-only over the ride |
| `RideRemoteControlling` | Sends status; receives `RideRemoteCommand` with a reply (`accepted`/`ignored(reason)`) | Noop/Fake now; WatchConnectivity in the watch spec |
| `RideRemoteBridge` | Maps commands to existing `RideSessionViewModel` intents (`pause`, `resume`, `stop`), to `ClipPinner` (save clip), and to the crash coordinator (cancel). `stop` is ignored unless `confirmedByHold` | Ride engine unchanged |
| `AlertSink` + `FanOutAlertManager` | One sink per channel; the fan-out is the `AlertManager` the rest of the app already calls | `AlertManager` unchanged |
| `AlertRoutingPolicy` | Pure: (kind × channel availability × app context) → ordered sinks, with per-kind cooldowns | Test-first |

### Commands

| Command | Allowed | Notes |
| ------- | ------- | ----- |
| pause / resume | yes | idempotent; ignored when the engine is not in a valid state |
| saveClip | yes | debounced 2 s; reply says saved/pending/nothing-to-save |
| stop | yes, only with `confirmedByHold` | prevents an accidental wrist tap from ending a ride |
| cancelCrashCountdown | yes, while a countdown is active | cross-reference below |
| startRide | **no** (v1) | the ride is started and framed on the phone |

### Routing table (policy defaults)

| Alert | Watch reachable | No watch, headphones | No watch, speaker only | Phone locked / backgrounded |
| ----- | --------------- | -------------------- | ---------------------- | --------------------------- |
| `cautionRearVehicle` | strong haptic (+ optional soft audio) | audio blip | speaker blip (wind-limited, honest limit) | dropped (stale) |
| `cameraInterrupted` | double haptic + text | spoken "camera paused" | spoken | local notification (mirrors to watch) |
| `cameraResumed` | light haptic | short tone | short tone | — |
| `cameraStopped(reason)` | long haptic + text | spoken | spoken | local notification |
| `clipSaved` / `clipNotSaved` | light / double haptic | tick / buzz-tone | tick | — |
| `phoneBatteryLow` | haptic + text | spoken once | spoken once | notification |
| crash countdown (crash spec) | all channels, repeating | speech + tones | speech + tones (loud) | notification (crash spec) |

Cooldowns: rear-vehicle caution at most once per 3 s; camera notices at most once per minute per
reason. Audio uses a category that mixes with other audio. Sinks that fail never affect recording.

### Apple Watch recommendation (O-CAM1)

Recommended as the in-ride surface: start excluded; pause/resume, save clip, hold-to-stop, live
ride time/distance (clock ticked locally from an anchor), camera/storage/battery state, wrist
haptics for rear-vehicle caution and camera trouble, and crash-countdown cancel. Open feasibility
risks for the watch spec: keeping the watch app running (workout session), reachability and latency,
notification mirroring does not apply while the phone screen is on (capability row 10). If the owner
has no watch, the fallback is audio plus the unlock gesture; a handlebar Bluetooth shutter remote
for "Save clip" is a Stretch option (row 18).

### Crash-response cross-reference

- The countdown takeover (`CrashCountdownHost`) already sits above the ride cover. Add the
  following behavior at integration time (task 30): on countdown start ride mode forces full
  brightness and unlock (screen row 10); the spoken countdown prompt mentions the watch when
  reachable; `RideStatus.crashCountdownDeadline` is published; `cancelCrashCountdown` is accepted from
  the remote. Consent copy states that without a watch the phone must be reachable to cancel.
- Footage: `ClipFootageBuffer` implements crash-response's `FootageBuffer` seam.

| Crash-response `FootageBuffer` member | Behavior here |
| -------------------------------------- | ------------- |
| `preserve(eventId, around: detectedAt)` | Request a `crash` pin (60 s / 30 s). Returns the new clip's id immediately as the opaque local reference (post-roll pending), or none if the camera is not recording |
| `delete(reference)` | Delete the clip (files, thumbnail, record) |
| Never | upload, attach, link, or put the reference in any message (`NOFOOT`) |

---

## Detection events and near-miss records

`DetectionCoordinator` (main actor) owns the detector lifecycle and applies `NearMissPolicy`:

| Input | Decision |
| ----- | -------- |
| `HazardDetection` with confidence below the configured threshold | Ignore (still available for alert policy if the owner wants a lower alert threshold) |
| Above threshold, cooldown not elapsed | Count as part of the same event; no new pin |
| Above threshold, per-ride cap reached | Record the event; no pin |
| Above threshold, eligible | New `NearMissEvent` (route point looked up by timestamp from the ride bridge); pin a detection clip if enabled and storage allows; link the clip id locally |
| Detection arrives while the camera is `interrupted`/`stopped` | Cannot normally happen; if it does, record the event without a clip |

`NearMissUploadMapper` (pure) converts an event to the contract shape for Role C's `near_misses`
table: ride id, occurred-at, latitude, longitude, kind, confidence, position hint — **dropping**
the local clip id and everything else. A unit test asserts that no footage-related field can reach
the mapped value. Actual upload is a separate future task behind opt-in ride sync.

---

## Privacy and network invariants

- Footage, thumbnails, segment files, and exported temp files are never written to logs, never
  uploaded, never in a crash message, and excluded from backups.
- **Amended invariant (unchanged in substance):** while neither ride sync nor crash alerts is
  enabled, the app makes no network requests. Camera code makes none; it is not allowed to import
  networking APIs (existing rule 1 already flags `URLSession` outside `Services/Sync`; crash-response
  also permits `Services/Notification`).
- Permission moments: camera when "Record rear camera" is first enabled; microphone only when audio is
  enabled; Photos add-only at the first explicit export; notifications at the first camera-notice need
  (after enabling recording, with an in-app explanation).
- **`scripts/privacy-check.sh` changes (a task; not made in this job):**
  1. Replace rule 7: capture/writer APIs (`AVCaptureSession`, `AVCaptureDevice`, `AVCaptureVideoDataOutput`,
     `AVCaptureAudioDataOutput`, `AVCaptureMovieFileOutput`, `AVAssetWriter`, `AVCaptureDevice.requestAccess`)
     only in `Services/Camera/`. Remove the allowance for `Services/Detection`.
  2. New: `import Photos` / `PHPhotoLibrary` only in `Services/Camera/PhotosClipExporter.swift`.
  3. New: `import WatchConnectivity` only in `Services/Remote/`.
  4. New: `UIScreen` brightness writes and `isIdleTimerDisabled` only in `Services/Screen/` (the
     existing `ActiveRideView` call is migrated first).
  5. New: Core Motion also allowed in `Services/Camera/` (crash-response's rule keeps `Services/Crash/`).
  6. New: files under `Services/Sync/` and `Services/Notification/` must not reference camera, clip, or
     footage types (`VideoFrame`, `ClipRecord`, `Segment`, `FootageBuffer`, `AVAsset`, `.mp4`, `.mov`).
  7. Copy rule extension: flag copy that claims recorded footage is evidence or that capture is assured
     (phrased to avoid colliding with rule 4's patterns).
  8. Models/Metrics must not import AVFoundation, CoreMedia, CoreVideo, Photos, or CoreMotion
     (extends rule 5).
- Existing hooks (`privacy-guard-on-save`, tests) apply unchanged once the script is updated.

---

## Error and degradation handling

| Scenario | Behavior | Req |
| -------- | -------- | --- |
| Camera permission denied/restricted | Toggle explains; ride continues without video; Settings path | 2.3, 17.1 |
| Permission revoked mid-ride | Stop camera cleanly; alert; ride continues | 2.4 |
| No camera hardware / unsupported profile | Nearest supported profile or `unavailable`; ride continues | 3.2, 17.1 |
| Interruption (lock, call, other app) | Finalize; notice after 5 s; resume on return | 11 |
| Thermal serious / critical | Reduce, then stop camera; GPS continues; announced | 12.1 |
| Low storage | Warn, stop auto-pins, then stop camera; announced | 12.2 |
| Low battery | Suggest Efficient; stop camera at floor; announced | 12.3 |
| Writer failure | Discard segment, one restart, else failed + alert | 17.2 |
| App killed mid-ride | Orphan segments purged on launch; clips kept; ride recovery as before | 17.3 |
| Consumer slow/crashing | Others and recording unaffected; stats show drops | 4.7, 17.4 |
| Watch unreachable | Audio sinks carry alerts; commands unavailable; recording unaffected | 13 |
| Brightness not restored by a previous run | Persisted guard restores on launch | 10.2 |
| Pinned storage cap reached | "Storage full for clips" on manual save; auto-pins stopped | 6.6 |
| Clip export denied | Plain message; clip stays | 8.8 |
| Corrupt clip/segment file | Skip with calm notice; offer delete | 8 |

---

## Testing strategy

All logic is unit-tested with fakes; pure policies and reducers are table-driven. Manual device
checks go in `manual-qa.md` (task 31).

| ID | Area | Scenario → assertion |
| -- | ---- | -------------------- |
| RB-1…8 | Ring buffer | Under/at/over duration and byte bounds; oldest first; ties; never evicts open/pinned/pending; empty set; shrinking cap; out-of-order registration |
| CW-1…10 | Clip windows | Normal, clamped at ride start, future post-roll, ride ends early, gap, none available, coalesce overlap/near-adjacent, coalesce over max duration, cap reached, link-shared boundary segment |
| TP-1…8 | Thermal policy | Each level; step-down order (fps then resolution); critical stops; hysteresis up; no two-step jump; consumers half-rate at serious |
| SP-1…6 | Storage/battery policy | start/warn/stop thresholds; effective ring cap shrink; charging override; LPM ⇒ Efficient |
| CS-1…8 | Profile selector | Requested vs supported; thermal/battery adjustments; fallback; unavailable |
| FD-1…8 | Frame-drop policy | Table above, including jitter tolerance, backward clock, large gap |
| FP-1…8 | Frame pipeline | No consumers ⇒ zero work; slow consumer drops older frames; two consumers independent; add/remove while running; busy-drop counts; no more than 1 in-flight + 1 pending; discontinuity flag after restart; fake source ordering |
| CM-1…24 | Camera reducer | One test per row of the table |
| SM-1…15 | Screen-mode reducer | One test per row; crash forcing; resign-active restore |
| BG-1…6 | Brightness guard | Restore, rider-changed, already-equal, persisted guard, repeated enter |
| LV-1…6 | Level calculator | Orientations, thresholds, noise |
| RE-1…10 | Readiness evaluator | Each row pass/warn/block |
| NM-1…8 | Near-miss policy | Threshold, cooldown, per-ride cap, storage refusal, no-clip event |
| AR-1…8 | Alert routing | Every kind × availability combination; cooldowns |
| UP-1 | Upload mapper | No clip id/video/thumbnail field can survive mapping |
| MAN-1…4 | Manual save | Debounce; nothing to save; storage full; success |
| CL-1…6 | Clip lifecycle | Retention sweep, delete one/all/ride cascade, expiry, real file deletion (temp dir), orphan purge |
| FB-1…4 | Footage buffer | preserve returns reference immediately; none when not recording; delete removes files; never blocks |
| RC-1…6 | Remote bridge | Commands map to intents; `stop` ignored without hold; pause/resume idempotent; cancel crash; unknown ignored |
| PERM-1…4 | Permissions | Enum mapping; denial flows; revoke mid-ride |
| UI | Views | Previews with fake camera; accessibility labels/traits asserted where practical |

Manual (device, not automatable): capture start latency; interruption by lock/call; fragment
recovery after kill; brightness restore after force-quit; Auto-Brightness fighting the setting;
touch lock in rain-like conditions; two-finger unlock reliability with gloves/wet fingers;
background GPS with screen locked; thermal/battery protocol; vibration blur on a real mount;
WatchConnectivity (watch spec).

---

## Decisions

| #   | Decision | Choice | Why | Status |
| --- | -------- | ------ | --- | ------ |
| D-CAM1 | In-ride surface | Apple Watch companion (separate spec) + audio fallback; seams defined here | Rear-mounted phone is unreachable; wrist haptics are felt | **OPEN O-CAM1** (recommended) |
| D-CAM2 | Record while screen "off" | Foreground ride mode (black, min brightness, touch-locked, idle timer off); no entitlement reliance | iOS interrupts background/locked capture; multitasking entitlement doesn't apply | Proposed (verified findings) |
| D-CAM3 | Locked-phone behavior | Camera stops cleanly, gap recorded, rider notified; GPS continues via `location` mode | Honest and keeps the route | **OPEN O-CAM2** (recommend enable) |
| D-CAM4 | Capture | Back wide camera, Standard 1080p30 / Efficient 720p30 / Reduced; HEVC; stabilization; locked orientation | Quality vs thermal/storage | Proposed (numbers *verify*; O-CAM3) |
| D-CAM5 | Frame seam | `FramePipeline` + `FrameConsumer`, latest-wins single slot, never blocks capture/writer | Lets B plug in without touching capture | Proposed (contract freeze 3-way) |
| D-CAM6 | Recording | One writer per 15 s segment; fragments; ring bounded by minutes and bytes | Simple, recoverable, bounded | Proposed (O-CAM3 for numbers) |
| D-CAM7 | Pinning | Hard links into per-clip folders (copy fallback); coalescing windows; pre/post by source | Cheap, no re-encode, safe from eviction | Proposed |
| D-CAM8 | Clip metadata | Separate `ClipRepository` (SwiftData), not columns on `RideRecord` | Avoids migrating the shipped ride model; cascade via cleanup hook | Proposed |
| D-CAM9 | Retention | Ring cleared at ride end; saved clips expire after 30 days unless kept | Privacy by default | **OPEN O-CAM4** |
| D-CAM10 | Audio | Off by default; mic permission only if enabled; Stretch | Conversations are sensitive | **OPEN O-CAM5** (recommend defer) |
| D-CAM11 | Ride mode | Optional; two-finger long press unlock; red dot always visible; no hiding of system indicators | Honest, safe | Proposed |
| D-CAM12 | Camera during pause | Keeps recording while the ride is paused (`recordWhilePaused` on) | Traffic still passes at a stop; footage useful | Proposed |
| D-CAM13 | Detection pinning | Off until Teammate B supplies measured thresholds; capped per ride | False positives would fill storage | Proposed (O-CAM6) |
| D-CAM14 | Ride engine | Unchanged; `RideCameraBridge` / `RideRemoteBridge` read it and call existing intents | Keeps the finished MVP stable | Proposed |
| D-CAM15 | Export | Photos add-only via `PhotosClipExporter` on explicit action; share-sheet alternative documented | Matches owner's "Photos only by explicit action" | Proposed |
| D-CAM16 | Folder map | `Services/Camera`, `Services/Screen`, `Services/Remote`, `Features/Camera` | Mirrors crash-response style; enables narrow privacy rules | Proposed |
| D-CAM17 | Demo-mode | Independent; simulated detections use the same pipeline; clips tagged demo | Judges can see clips without a bike | Proposed (coordinate with `../demo-mode/`) |

### Owner resolution (October 24, 2026)

The iOS owner approved this spec and accepted every recommendation; this table is binding.

| # | Resolution |
| - | ---------- |
| O-CAM1 | Apple Watch companion is the in-ride control and alert surface, specified in its own follow-up spec. This spec defines only its seams (`RideStatus`, `RideRemoteControl`, `AlertSink` fan-out). |
| O-CAM2 | Enable the `location` background mode now (When-In-Use + `allowsBackgroundLocationUpdates` + blue indicator). |
| O-CAM3 | Defaults: Standard 1080p30 HEVC at about 5 Mbps, 10-minute ring buffer capped at 1 GB, 2 GB cap on saved clips. These are hypotheses to measure on the iPhone 14 and tune. |
| O-CAM4 | Saved clips auto-delete after 30 days. |
| O-CAM5 | No audio recording for now (off by default; no microphone permission). |
| O-CAM6 | Detections may auto-save clips, capped at 10 per ride, but this stays off until Teammate B supplies measured thresholds. |

### Open decisions for the owner (now resolved above)

| # | Question | Recommendation | Affects |
| - | -------- | -------------- | ------- |
| **O-CAM1** | Adopt an Apple Watch companion as the in-ride control and alert surface (separate follow-up spec)? Does the owner or a teammate own a watch for development? | **Yes.** Define the seams now (tasks 10, 13, 29); write the watch spec next (task 34); ship audio + unlock gesture as the no-watch fallback. | Requirement 13; tasks 13, 29, 34 |
| **O-CAM2** | Enable the `location` background mode now (When-In-Use + background updates + indicator), and what to do with crash-response O1(b)? | **Enable now** (task 24); keep crash v1 at (a)+(c) but note (b) is now cheap to adopt. Confirm Apple's review wording and device behavior. | Requirements 11.5; task 24; crash task 35 |
| **O-CAM3** | Default capture and buffer numbers: Standard 1080p30 HEVC 5 Mbps vs Efficient 720p30 default; segment 15 s; ring 10 min / 1 GB; pinned cap 2 GB | Start Standard for demo clarity; default to Efficient in Low Power Mode; revisit after task 31. | Requirements 3, 5, 12 |
| **O-CAM4** | Saved-clip retention: 30 days then auto-delete (with "Keep") vs keep until deleted | 30 days, with Keep as a Stretch. | Requirement 8.7 |
| **O-CAM5** | Audio recording: include as a Stretch (off by default) or defer entirely | Defer; Stretch task 33. | Requirement 14 |
| **O-CAM6** | Should detection events auto-pin clips by default once Teammate B supplies thresholds? | Yes, capped (10/ride) and off until measured numbers exist. | Requirement 15; task 28 |

---

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| **Heat on a seat post in sun** (dark phone, direct sun, charging) | Throttling, forced camera stop, shortened battery | Thermal policy (reduce then stop), ride mode (dim screen), mount-time tip (light case, shade, avoid charging in heat), announced degradation, measure in task 31 |
| **Vibration blur / rolling shutter** | Footage and detection quality | Stabilization where supported, exposure cap, field test on a real mount; mount advice; detector tolerates blur (B) |
| **Rain and lens droplets/fog** | Unusable footage; touch noise | Touch lock, lens-wipe reminder, no waterproof claim, dark/blur hint |
| **Battery drain** (camera + GPS + display) | Ride ends early | Dim OLED, Efficient/Reduced profiles, battery policy stops camera before GPS, power-bank guidance, budgets measured |
| **Storage** | Phone fills | Bounded ring, clip cap, free-space guard, ring cleared at ride end, retention |
| **Interruption looks like normal operation** (rider can't see) | False sense of footage | Every stop/degrade announced; red→amber dot; summary notes gaps |
| **Phone falls off the mount** | Lost phone, injury risk to others | Secure-mount reminder in the checklist; no claim; crash detector stretch must handle mount drops |
| **Other people in footage** (faces, plates) | Privacy, legal differences | Local-only, short retention, easy deletion, guidance, no auto-upload, informational note on local laws |
| **Hidden-recording perception** | Trust, legal | Red dot always on; system indicators untouched; copy never says "hidden" |
| **Watch dependency** | Reachability/battery/latency unknown | Seams + audio fallback; watch spec starts with a feasibility spike |
| **Capture/writer bugs on device** | Corrupt files, dropped frames | Fragments, segment isolation, orphan purge, device QA |
| **Brightness not restored** | Rider's phone left dim | Restore on all exits + persisted guard + launch restore |
| **Mixed consumer load** | Detector starves capture or overheats | Latest-wins slot, consumer fps cap, thermal throttling of consumers |
| **Background-mode review risk** | App Review question | Standard fitness justification; When-In-Use only; indicator shown |
| **Demo-mode divergence** | Two specs disagree | Coordinate at owner review (Requirement 18.5) |
| **Overclaiming** | Trust | Honest copy rules; "experimental" framing; privacy script copy rules |
