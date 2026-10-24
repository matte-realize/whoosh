# Whoosh — Technology & Conventions

## Platform

- **Language:** Swift 6 toolchain (Xcode 26.5)
- **UI:** SwiftUI
- **Minimum target:** iOS 17.0
  - Enables the Observation framework (`@Observable`), modern MapKit SwiftUI APIs,
    and SwiftData. Chosen to reduce boilerplate during a hackathon.
  - Primary demo device: iPhone 14. iOS 17 keeps teammates' older phones supported.
- **IDE / project:** Xcode 26.5 with a standard, committed `.xcodeproj` (no XcodeGen).
  The iOS owner is the only person editing the project file, so merge conflicts are unlikely.
- **Apple Developer account:** available. Use it for on-device installs, entitlements, and
  capabilities (e.g., background location later) without free-account limits.
- **Concurrency:** Xcode 26 defaults. Default actor isolation = `MainActor`, Approachable
  Concurrency on. View models, the location wrapper, and repositories run on the main actor.
  Heavy work (camera frames, model inference, network sync) must be explicitly moved off the
  main actor (`nonisolated`, `@concurrent`, or a dedicated actor).
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
| Camera (future)      | AVFoundation                      | Isolated; not in demo path.                  |
| Detection (future)   | Vision / Core ML                  | Behind `HazardDetector` protocol only.       |
| Alerts (future)      | Core Haptics / AVAudioSession     | Behind `AlertManager` protocol.              |
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
    Detection/         HazardDetector protocol + NoopDetector (future)
    Alerts/            AlertManager protocol + stub (future)
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
