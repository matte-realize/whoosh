# Whoosh — Technology & Conventions

## Platform

- **Language:** Swift 6 toolchain (Xcode 26.5)
- **UI:** SwiftUI
- **Minimum target:** iOS 17.0
  - Enables the Observation framework (`@Observable`), modern MapKit SwiftUI APIs,
    and SwiftData. Chosen to reduce boilerplate during a hackathon.
  - Primary demo device: iPhone 14. iOS 17 keeps teammates' older phones supported.
- **IDE / project:** Xcode 26.5. The committed `Whoosh.xcodeproj` is the source of truth and
  can be opened directly. _Amended:_ the original "no XcodeGen" decision is revised —
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) is used **only as a one-time generator**
  from a repo-root `project.yml` (which documents the build settings in one place); the
  generated `.xcodeproj` is committed. Sources use Xcode's file-system-synchronized groups
  (`type: syncedFolder`), so new `.swift` files under `Whoosh/` or `WhooshTests/` are compiled
  automatically without regenerating. Regenerate only when `project.yml` settings change
  (`xcodegen generate`). The iOS owner is the only person editing the project, so merge
  conflicts are unlikely.
- **Apple Developer account:** available. Use it for on-device installs, entitlements, and
  capabilities without free-account limits.
- **Background location decision (rear-camera spec, O-CAM2):** the MVP was foreground-only. A
  rear-mounted phone locks or backgrounds more easily and iOS interrupts a camera session when it
  does, so the recommendation is to declare `UIBackgroundModes` = `location` now and, **only while a
  ride is active and started from the foreground**, enable background updates with the
  background-location indicator under **When-In-Use** authorization (no
  `NSLocationAlwaysAndWhenInUseUsageDescription` needed for this). Video still cannot record while
  locked; the multitasking camera entitlement does not apply to this use (it covers Slide Over,
  Split View, and Picture in Picture and is restricted to `voip` apps). Re-checked against Apple docs
  on October 24, 2026; confirm on device.
- **Concurrency:** Xcode 26 defaults. Default actor isolation = `MainActor`, Approachable
  Concurrency on. View models, the location wrapper, and repositories run on the main actor.
  Heavy work (camera frames, model inference, network sync) must be explicitly moved off the
  main actor (`nonisolated`, `@concurrent`, or a dedicated actor). For the camera: the capture
  session, sample-buffer callbacks, and the asset writer run on dedicated serial queues; frame
  consumers run on their own executors; `CVPixelBuffer` crosses actors only inside the documented
  `VideoFrame` wrapper; only state and intents reach the main actor.
- **Units:** US customary. Miles, mph, feet. Internal storage stays SI (meters, seconds,
  m/s); conversion happens only in the formatting layer.

## Frameworks

| Concern              | Framework                         | Notes                                        |
| -------------------- | --------------------------------- | -------------------------------------------- |
| UI                   | SwiftUI                           | Views are thin; logic lives in view models.  |
| State / observation  | Observation (`@Observable`)       | Prefer over `ObservableObject` on iOS 17+.   |
| Maps                 | MapKit (`Map`, `MapPolyline`)     | No API key, no cost.                          |
| Location             | Core Location                     | `CLLocationManager` behind a protocol.       |
| Persistence          | SwiftData                         | Local source of truth; swappable via repo.   |
| Cloud sync (opt-in)  | Supabase (`supabase-swift`, pinned)| Behind `RideSyncService`; never required.    |
| Camera capture + recording | AVFoundation (`AVCaptureSession`, `AVAssetWriter`) | **In scope** (rear-camera spec). Only in `Services/Camera/`, behind `CameraCapturing`; off the main actor. |
| Clip playback / export | AVKit, AVFoundation composition, PhotoKit (add-only) | Playback in the app; Photos export only in `Services/Camera/PhotosClipExporter.swift`, on explicit rider action. |
| Mount level indicator | Core Motion                      | `Services/Camera/` (also `Services/Crash/` for the stretch detector). |
| Screen dim mode      | UIKit (screen brightness, idle timer) | Only in `Services/Screen/`, behind `ScreenController`; restore on every exit. |
| Background location  | Core Location (`location` background mode) | Recommended now (open decision O-CAM2): When-In-Use + background updates + indicator, only during a ride; no Always prompt. |
| Detection (future)   | Vision / Core ML                  | A `HazardDetector` that is also a `FrameConsumer`; never owns capture. |
| Alerts               | Core Haptics / AVAudioSession / local notifications | `AlertSink`s behind the unchanged `AlertManager` (fan-out); audio/watch channels. |
| In-ride remote (future) | WatchConnectivity (Apple Watch companion) | Separate spec (O-CAM1); only in `Services/Remote/`, behind `RideRemoteControl`. |
| Testing              | Swift Testing                     | `@Test`, `#expect`, parameterized tables.    |

## Architecture

MVVM with a service layer. Dependencies flow through protocols so teammates can
implement services independently and tests can inject fakes.

```
SwiftUI Views  ->  ViewModels (@Observable)  ->  Service protocols  ->  Implementations
                                                       |
                                                 Repositories (SwiftData)
```

Key rules:

- **Views are dumb.** No business logic, no direct framework calls (no `CLLocationManager`
  inside a `View`). Views observe a view model and send intents.
- **Services are protocols.** `LocationTracking`, `RideRepository`, `RideSyncService`,
  `HazardDetector`, `AlertManager`. Concrete types (`CoreLocationTracker`,
  `SwiftDataRideRepository`, `SupabaseRideSyncService`) are injected. Fakes back the tests.
- **Local-first.** SwiftData is the source of truth. The app records, summarizes, and shows
  history fully offline. Supabase sync is an opt-in add-on that uploads finished rides; a
  sync failure never affects recording or local data.
- **Backend contract before code.** The Supabase schema is owned by Role C and lives in
  `.kiro/team/supabase-contract.md`. The app implements against it only once it's marked
  agreed.
- **State machines over booleans.** Ride state and permission state are explicit enums.

## Project Layout (proposed)

```
Whoosh/
  App/                 App entry, root navigation
  Features/
    Ride/              Recording flow: views + view models
    Summary/           Ride summary views
    History/           Past rides list
  Services/
    Location/          LocationTracking protocol + CoreLocationTracker + Fake
    Persistence/       RideRepository protocol + SwiftData impl + models
    Sync/              RideSyncService protocol + Noop + Supabase impl (later)
    Detection/         HazardDetector protocol + NoopDetector; DetectionCoordinator (frames via FramePipeline)
    Camera/            Capture, FramePipeline/FrameConsumer, segment recorder, ring buffer, clips, Photos export (rear-camera spec)
    Screen/            ScreenController (brightness, idle timer) for ride mode
    Remote/            RideRemoteControl seam (Noop/Fake now; WatchConnectivity later)
    Alerts/            AlertManager protocol + stub; AlertSink fan-out (rear-camera spec)
  Models/              Domain models (Ride, RoutePoint, RideState)
  Support/             Extensions, formatters, permission helpers
WhooshTests/           Unit tests with fakes
```

## Coding Conventions

- Prefer value types (`struct`) for domain models; `@Model` classes only for SwiftData.
- One type per file; file name matches the type.
- Keep functions small and pure where possible so they're unit-testable.
- No force-unwraps (`!`) in non-test code except for compile-time constants.
- Use `async/await` for asynchronous work; avoid completion-handler pyramids.
- Document any permission request with a clear usage-description string.
- Pin dependency versions exactly (Swift Package Manager "Exact Version").
- Never commit secrets. Supabase URL and anon key live in a gitignored `Secrets.xcconfig`;
  a committed `Secrets.example.xcconfig` documents the keys. The `service_role` key must
  never appear in the app or the repo.

## Build & Test

- Build and test from Xcode, or `xcodebuild` on CI.
- Run unit tests before marking any task complete.
- Target: logic (view models, services, repositories) is unit-tested with fakes.
  UI and real Core Location/AVFoundation integration are verified manually on device.
- Camera: the capture service, asset writer, brightness control, background location, and thermal/
  battery behavior cannot be exercised by the simulator; they are verified on the iPhone 14 and
  logged in `.kiro/specs/rear-camera/manual-qa.md`. Pure policies (ring buffer, clip windows,
  thermal/storage/battery, frame dropping, screen-mode and camera state machines) are test-first
  with a controllable `Clock` and no AVFoundation.
