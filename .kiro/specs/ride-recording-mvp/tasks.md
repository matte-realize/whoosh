# Implementation Plan — Whoosh Ride Recording MVP (iOS)

Small, ordered, verifiable tasks for the **iOS app owner**. Each task builds on the previous.
Run the unit test suite before marking a task done. Tasks that touch real Core Location /
MapKit also require a brief manual device/simulator check, called out explicitly.

This plan covers only the iOS ride-recording MVP. Cross-team ownership (vision, backend/data)
lives in `../../team/team-plan.md`. The future-seam tasks here (task 22) are what the vision
and alert work will plug into.

Spec status: approved by the iOS owner (October 24, 2026); implementation may proceed task by task.

Conventions:
- `(test-first)` means write failing unit tests from the referenced acceptance criteria,
  then implement until green.
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers.
- Each task is intended to be a single reviewable commit (or a small PR).

---

- [x] 1. Project scaffolding and app foundation
  - Create a standard Xcode 26.5 project (committed `.xcodeproj`, iOS 17 deployment target,
    SwiftUI app lifecycle, Xcode 26 default concurrency settings) and the folder layout from
    the tech steering: `App/`, `Features/`, `Services/`, `Models/`, `Support/`, `WhooshTests/`.
  - Add Info.plist usage-description strings: `NSLocationWhenInUseUsageDescription` (active
    now) and `NSCameraUsageDescription` (groundwork, unused by MVP).
  - Add `Secrets.example.xcconfig` (placeholder `SUPABASE_URL`, `SUPABASE_ANON_KEY`) and wire
    a gitignored `Secrets.xcconfig` into the build settings. The app must build with the
    placeholders.
  - Add a Swift Testing unit test target with one trivial `@Test` to prove the pipeline runs.
  - Set the signing team from the Apple Developer account so the app installs on the iPhone 14.
  - _Verify:_ app builds and launches to a placeholder home screen on an iOS 17+ simulator and
    on the iPhone 14 with no first-party warnings; `xcodebuild test` passes.
  - _Requirements: 1.3, 9.1_
  - _Pending device check:_ `build-for-testing` succeeds for the simulator with no first-party
    warnings and the synced-folder auto-compile was verified. Launching on-device (iPhone 14)
    and running the full simulator test run are left to the orchestrator (no simulator/device
    boot in this task).

- [x] 2. Design system and theme (Support/)
  - Build `Theme` in `Support/` with the color tokens Ink `#0B0F14`, Lime `#C8F135`, Amber
    `#F5A524`, Alert `#D32F2F`, Mist `#F4F5F7` (asset-backed), and SF Pro typography with large
    bold tabular (monospacedDigit) numerals for ride metrics.
  - Build the shared components: `PrimaryButton` (lime, ≥60pt), `StateChip` (icon + text),
    `StatTile`, and `RideRow`. Encode the principles: three numbers max while riding, thumb-
    zone controls with ≥60pt targets, icon + text for every state. Light chrome, dark ride.
  - _Verify:_ a tiny preview screen renders each component in light and dark; metric numerals
    are tabular; build has no first-party warnings.
  - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 10.5, 10.6_
  - _Depends on: 1_
  - _Pending device check:_ code written and `build-for-testing` succeeds with no first-party
    warnings; `scripts/privacy-check.sh` passes. Colors are defined in code as light/dark
    dynamic `Color` tokens (`Support/Theme/Theme.swift` + `Color+Theme.swift`) rather than an
    asset catalog, so the five brand hues live in one reviewable place with sensible light/dark
    semantic roles. Components (`PrimaryButton`, `StateChip` with recording/paused/signalLost/
    gpsReady/rearDetectionOff/synced/pending/onDevice variants, `StatTile`, `RideRow`, plus a
    `RouteGlyph` mini-polyline) live in `Support/Components/` with a `#Preview` `ComponentGallery`
    in light + dark. Visual rendering and Dynamic Type are verified on device by the orchestrator.

- [x] 3. Domain models (pure)
  - Implement `RoutePoint`, `RideSummary`, `Ride`, `RideState`, and the `RideTuning` config
    struct with documented defaults.
  - Ensure Models import Foundation only (no SwiftUI/CoreLocation/SwiftData/MapKit), per the
    layering table.
  - _Verify:_ models compile in the test target and are `Equatable`/`Codable` where specified.
  - _Requirements: 3.5, 4.2, 4.3_
  - _Depends on: 1_

- [x] 4. Ride metrics (pure, test-first)
  - Implement `RideMetrics.distanceMeters`, `averageSpeed`, and `summary`.
  - Unit tests: empty → zeros; single point → zero distance; two points → known distance
    within tolerance; a multi-point fixture with a hand-computed expected distance; duration
    0 → average speed 0 (no NaN/divide-by-zero).
  - _Requirements: 6.2, 6.3, 6.4_
  - _Depends on: 3_

- [x] 5. Weekly stats aggregation (pure, test-first)
  - Implement `WeeklyStats` and `WeeklyStatsCalculator.compute(rides:now:calendar:)` in the
    Metrics layer (Foundation only). Output: `totalDistanceMeters`, `rideCount`,
    `totalActiveDuration`, and `distancePerWeekday` (Mon–Sun, length 7).
  - Unit tests (test-first): no rides; rides outside the current week; rides on the week
    start/end boundaries (half-open interval); a week spanning a DST change; zero-distance
    rides; correct Mon→Sun bucketing and totals.
  - _Requirements: 13.4, 13.5, 13.6_
  - _Depends on: 3_

- [x] 6. Clock seam (test-first)
  - Define the `Clock` protocol with `SystemClock` and `TestClock` (manual time advance +
    deterministic scheduled-work firing).
  - Unit tests: scheduled work fires after advancing past the interval; cancellation works.
  - _Requirements: 4.6 (testable timing foundation)_

- [x] 7. RideRepository protocol + in-memory fake (test-first)
  - Define `RideRepository` (including `deleteAll()`) and `InMemoryRideRepository`.
  - Unit tests: save; `allRides` returns most-recent-first; `ride(id:)` hit/miss; `delete`
    removes permanently; deleting a missing id is a safe no-op; `deleteAll` wipes everything.
  - _Requirements: 7.5, 7.2, 7.4, 7.8_
  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; the full `xcodebuild test` run is left to the orchestrator.
  - _Depends on: 3_

- [x] 8. SwiftData persistence implementation (test-first)
  - Define `RideRecord` `@Model` (points stored as an encoded blob) and
    `SwiftDataRideRepository` with `Ride` ↔ `RideRecord` mapping, implementing `deleteAll()`.
  - Wrap point decoding so a corrupt record is skipped (logged), not thrown.
  - Unit tests against an in-memory SwiftData container: save/list/get/delete; `deleteAll`
    permanently clears storage; most-recent-first ordering; permanence across container
    reload; corrupt-record skip.
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.6, 7.7, 7.8_
  - _Depends on: 3, 7_
  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; the full `xcodebuild test` run (incl. file-backed reload cases) is
    left to the orchestrator.

- [x] 9. LocationTracking protocol + fake (test-first)
  - Define `LocationTracking`, `LocationAuthorizationStatus`, `TrackingAccuracy`,
    `LocationFailure`, and `FakeLocationTracker` that scripts points, status changes, and
    failures on command.
  - Unit tests: fake delivers scripted callbacks in order; authorization change propagates.
  - _Requirements: 2.1, 4.1, 4.6_
  - _Depends on: 3_
  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; the full `xcodebuild test` run is left to the orchestrator.
    (`TrackingAccuracy` already existed in Models from task 3 and is reused, not redefined.)

- [x] 10. RideSessionViewModel state machine (test-first) — core of the MVP
  - Implement the `@Observable` view model owning `RideState`, injected `LocationTracking`,
    `Clock`, and `RideTuning`. Handle start/pause/resume/stop, acceptable-fix filtering
    (accuracy + plausible-speed/jump), the signal-loss timer, authorization-revoked-mid-ride,
    active-duration accumulation (excluding pauses), and finalize→compute→persist. Expose a
    single `stop` intent that both the press-and-hold gesture and the VoiceOver custom action
    call.
  - Unit tests: all 14 transition-table rows from the design, plus active-duration excludes
    paused spans, undefined transitions are no-ops, and finalize with zero points yields a
    zeroed summary.
  - _Requirements: 3.1–3.9, 4.1–4.7, 2.4, 11.1, 11.3_
  - _Depends on: 4, 6, 7, 9_
  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; the full `xcodebuild test` run is left to the orchestrator.

- [x] 11. CoreLocationTracker implementation
  - Implement `CoreLocationTracker` wrapping `CLLocationManager`: map `CLLocation`→`RoutePoint`,
    `CLAuthorizationStatus`→our enum, `didFailWithError`→`LocationFailure`; request
    When-In-Use; apply `TrackingAccuracy` to desiredAccuracy + distanceFilter; `stopUpdating`
    fully releases updates.
  - _Verify (device/sim):_ authorization prompt appears with the honest string; location
    updates flow; stopping ends updates (no leaked tracking).
  - _Requirements: 2.1, 4.1, 11.3_
  - _Depends on: 9_
  - _Pending device check:_ code written and `build-for-testing` succeeds with no first-party
    warnings. The pure mapping layer (`CoreLocationMapping`: status/accuracy/failure/CLLocation
    mapping) is unit-tested in `CoreLocationMappingTests`; the live `CLLocationManager` wrapper
    (auth prompt, real updates, stop releases tracking) is verified on device by the
    orchestrator. Delegate methods are `nonisolated` and hop to the main actor; no background
    modes / `allowsBackgroundLocationUpdates`; `activityType = .fitness`,
    `pausesLocationUpdatesAutomatically = false`.

- [x] 12. Formatters and unit policy (test-first)
  - Centralize formatting in US customary units: miles (2 decimals under 10 mi, 1 above),
    mph (1 decimal), feet for short distances; duration `m:ss` under an hour, `h:mm:ss` above.
    Conversion from SI happens only here.
  - Unit tests (parameterized): zero, typical, and large values; the 10-mile and 1-hour
    boundaries.
  - _Requirements: 10.1, 10.2_
  - _Depends on: 3_

- [x] 13. GPS-accuracy setting + SettingsViewModel (test-first)
  - Implement `SettingsViewModel` that reads/writes the GPS accuracy choice (Balanced / High)
    in `UserDefaults` and maps it to `RideTuning.accuracy`; the composition root feeds the
    persisted value into the next ride. Expose the "Delete all rides" intent calling
    `RideRepository.deleteAll()`.
  - Unit tests: accuracy persists and reloads across instances; maps to the correct
    `TrackingAccuracy`; delete-all calls the repository.
  - _Requirements: 14.2, 14.4_
  - _Depends on: 7, 9_
  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; the full `xcodebuild test` run is left to the orchestrator. Delete-all
    failure is reported via `deleteErrorMessage` (plain, non-raw copy) per Requirement 11.4.

- [x] 14. Settings screen
  - Build `SettingsView` (pushed from Home, back label "Home") using the design system:
    functional GPS-accuracy control; read-only "Units · Miles · mph"; destructive "Delete all
    rides" with a confirmation alert → `deleteAll()`. Show DISABLED "Coming soon" rows until
    sync ships: "Sync rides to Whoosh map" toggle (plain copy on what's uploaded + camera video
    never uploaded), "Privacy zone · 0.1 mi", "Identity · Anonymous"; plus a disabled "Rear
    vehicle detection · Soon" row (experimental, never requests camera).
  - _Verify (device/sim):_ accuracy choice survives relaunch; delete-all confirmation wipes
    history; disabled rows show "Coming soon"; no camera prompt.
  - _Requirements: 14.1, 14.3, 14.5, 14.6, 14.7, 12.1, 9.4_
  - _Depends on: 2, 13_
  - _Pending device check:_ `SettingsView` built per mockup 7 and bound to the existing
    `SettingsViewModel`; `build-for-testing` succeeds with no first-party warnings;
    privacy-check passes. The GPS-accuracy menu picker is bound to `viewModel.accuracy`
    (persistence + relaunch survival is unit-tested in `SettingsViewModelTests`). Delete-all
    uses a destructive confirmation alert calling `deleteAllRides()`, with a second alert
    surfacing `deleteErrorMessage`. Disabled sync rows + the "Soon" rear-detection row request
    nothing. Live relaunch/navigation and the no-camera-prompt behavior are verified on device
    by the orchestrator.

- [x] 15. Home screen, permission UX, and location-denied state
  - Build `HomeView` + `HomeViewModel` shell using the design system: primary Start Ride,
    entries to History and Settings, "GPS ready" status chip. Wire the location-denied state:
    explanation, a numbered Open-Settings help (1. Open Settings, 2. tap Location, 3. choose
    "While Using the App"), an Open-Settings deep link, and a "View past rides" button; keep
    history reachable; reflect live authorization changes; handle services-disabled the same
    way. Accessibility labels; state via icon + text.
  - _Verify (device/sim):_ deny path shows the numbered help and opens Settings; "View past
    rides" still opens history; live auth changes update the UI.
  - _Requirements: 1.1, 1.4, 1.6, 2.2, 2.3, 2.4, 2.6, 10.3, 10.5, 13.8_
  - _Depends on: 2, 10, 11, 14_
  - _Pending device check:_ `HomeViewModel` (`@Observable`) maps authorization to a `HomeState`
    (`ready` / `needsPermission` / `denied`), observes `onAuthorizationChange` for live updates,
    and loads finished rides only; `LocationDeniedView` renders the slashed-location icon,
    numbered 1-2-3 help, the privacy reassurance, a lime "Open Settings" deep link
    (`UIApplication.openSettingsURLString`, injected so previews/tests don't touch UIApplication),
    and a secondary "View past rides". `HomeView` exposes `onStartRide`/`onOpenHistory`/
    `onOpenSettings`/`onSelectRide` closures so task 23 wires navigation. Auth-state mapping and
    live changes are unit-tested in `HomeViewModelTests`; `build-for-testing` + privacy-check
    pass. The real deny→Settings deep link and live return-from-Settings flow are verified on
    device by the orchestrator. _Assumption:_ `servicesDisabled` is covered by the same denied
    view; the current `LocationAuthorizationStatus` surfaces device-wide disable as `.denied`.

- [x] 16. Home dashboard (weekly stats, recent rides, placeholders)
  - Flesh out `HomeView`/`HomeViewModel` to the mockup: wordmark, "Ready to ride?", a This-Week
    stats card (total miles, ride count, total active time, Mon–Sun 7-bar chart from
    `WeeklyStatsCalculator.compute` with injected `Clock`/`Calendar`), a Recent rides list
    (latest 2–3 + "See all" → History), and the "Rear vehicle detection — Experimental, coming
    soon" placeholder card (non-functional, no camera permission). Empty-week renders zeros and
    a friendly empty Recent list.
  - _Verify (device/sim):_ dashboard shows correct weekly numbers for seeded rides; empty state
    is friendly; "See all" opens History; placeholder card never prompts for camera.
  - _Requirements: 13.1, 13.2, 13.3, 13.6, 13.7, 1.2_
  - _Depends on: 5, 7, 15_
  - _Pending device check:_ `WeeklyStatsCard` renders the big tabular miles number, the
    "N rides · 1h 02m" subtitle, and a Mon–Sun 7-bar chart (ink bars for days with rides, a
    recessed baseline otherwise) with a single combined VoiceOver summary of per-day distances.
    The dashboard shows the lime-underlined wordmark, "Ready to ride?", up to 3 finished
    `RideRow`s with "See all ›", a dashed inert rear-detection card (no camera), a thumb-zone
    lime Start Ride, and the "GPS ready" chip; the empty state shows "Your first ride will show
    up here." Weekly numbers (totals, per-weekday buckets, week-boundary filtering), the
    recent-limit/ordering, finished-only filtering, and the empty state are unit-tested in
    `HomeViewModelTests`; `build-for-testing` + privacy-check pass. Visual rendering with real
    rides and the no-camera-prompt behavior are verified on device by the orchestrator.

- [x] 17. RouteMapView wrapper
  - Build a single `RouteMapView` that renders a polyline + current-location indicator and
    supports both live (growing) and static (full-route) modes, with reasonable auto-follow
    and manual-pan tolerance. This is the only MapKit touchpoint.
  - _Verify (device/sim):_ a sample polyline renders; auto-follow behaves.
  - _Requirements: 5.1, 5.6_
  - _Depends on: 1_
  - _Pending device check:_ `Support/Map/RouteMapView.swift` is the only file importing MapKit
    besides the Core Location tracker (verified by grep). It uses the iOS 17 SwiftUI `Map` with
    two `MapPolyline`s (a wide ink casing under a lime line), start/end `Annotation` markers, and
    a live user dot. `.live` mode auto-follows `currentLocation`, pauses follow on a manual pan
    (`onMapCameraChange`), and shows a lime recenter button; `.static` fits the full route with
    1.4× padding. Empty and single-point routes are handled without crashing (no polyline / a
    single marker / a sensible region). `build-for-testing` + privacy-check pass. Live map
    rendering, real auto-follow, and manual-pan tolerance are verified on device by the
    orchestrator.

- [x] 18. Active ride screen with live map, metrics, and hold-to-stop
  - Build `ActiveRideView` as a non-dismissible full-screen cover using `RouteMapView` and the
    dark theme: live route, at most three numbers (ride time large, distance, speed) via
    formatters, a state chip (Recording/Paused, icon+text), a non-functional "Rear detection
    off" chip, tap Pause/Resume, and a press-and-hold **Stop** (~1s) with visible hold progress
    plus a VoiceOver "Stop ride" custom action. Amber signal-lost banner "GPS signal lost —
    Your ride continues. Resuming...". Keep metric updates off the main-thread hot path.
  - _Verify (device/sim):_ route draws live on a short walk; Pause/Resume behave; a quick tap on
    Stop does NOT end the ride but a ~1s hold does (with progress); VoiceOver custom action
    stops the ride; the cover can't be swiped away; signal-lost banner appears when updates
    stall.
  - _Requirements: 1.5, 3.2, 3.3, 3.4, 3.9, 5.1, 5.2, 5.3, 5.4, 5.5, 5.7, 8.7, 10.3, 10.5_
  - _Depends on: 2, 10, 12, 17_
  - _Pending device check:_ `ActiveRideView` (Features/Ride) built per mockups 2/3 and
    `HoldToStopButton` (Support/Components) built; `build-for-testing` succeeds with no
    first-party warnings and `scripts/privacy-check.sh` passes. The screen is always dark
    (`preferredColorScheme(.dark)` + ride tokens), shows `RouteMapView` in `.live` mode (its
    built-in recenter handles manual-pan), a top-left Recording/Paused `StateChip`, a bottom-left
    inert "Rear detection off" chip, and a bottom sheet with a `TimelineView`-driven RIDE TIME
    (ticks every second off the pure `activeDuration(at:)`, which freezes while paused),
    DISTANCE/SPEED via `Formatters`, a lime Pause/Resume pill, and the red `HoldToStopButton`.
    Hold-to-stop is a ~1s `LongPressGesture` with a rising progress fill, a light impact haptic
    on start and a success haptic on completion, early-release cancel (no state change), a brief
    "Hold to stop" tap hint, an `accessibilityAction(named: "Stop ride")`, and the label "Stop
    ride, press and hold"; all drive the single `RideSessionViewModel.stop()`. The amber
    signal-lost / permission-revoked banner renders when `banner` is set, and
    `isIdleTimerDisabled` is toggled on appear/disappear. The real press-and-hold gesture
    (progress + accidental-tap rejection), the VoiceOver custom action, live map auto-follow,
    the non-swipeable cover, screen-awake behavior, and real haptics are verified on device by
    the orchestrator.

- [x] 19. Ride summary screen
  - Build `RideSummaryView` (full-route `RouteMapView` + distance/duration/avg speed via
    formatters) with a sync-status row (icon+text: On device / Pending / Synced), dismissed
    with "Done" after a ride and reused for history detail. (The "trimmed for privacy" note
    appears once sync exists.)
  - _Verify:_ summary shows correct values for a known recorded ride; zero/one-point ride
    renders sensibly; "Done" returns to Home; sync-status shows "On device".
  - _Requirements: 6.1, 6.3, 6.5, 6.6, 10.1, 1.4_
  - _Depends on: 2, 4, 12, 17_
  - _Pending device check:_ `RideSummaryView` (Features/Summary) built per mockup 4 with a
    `Presentation` enum (`justFinished` → "Ride complete" title + lime "Done"; `historyDetail`
    → the ride's date title, dismissed via the nav back control). Renders a static
    `RouteMapView`, a big DISTANCE tile, RIDE TIME + AVG SPEED tiles (all via `Formatters`), and
    a sync-status row (icon + text) driven by a new `SyncStatus` model enum
    (`localOnly`/`pending`/`synced`; everything is `.localOnly` → "On device" for now). 0/1-point
    rides show a friendly "No route recorded" placeholder instead of an empty map and never
    produce NaN (numbers come from the finalized, zeroed summary). `build-for-testing` succeeds
    with no first-party warnings; privacy-check passes. The live "Done" → Home dismissal and the
    reused history-detail push are wired by task 23; visual rendering is verified on device by
    the orchestrator.

- [x] 20. History list and deletion
  - Build `HistoryView` + `HistoryViewModel`: rides grouped by month under a header (month ride
    count + total miles), rows showing date/distance/duration and a sync-status indicator
    (icon+text; "On device" until sync exists), swipe-to-delete with a Delete button, tap-
    through to `RideSummaryView`, empty-state, and graceful skip of corrupt records.
  - _Verify (device/sim):_ rides persist across relaunch; month headers show correct counts and
    miles; swipe-to-delete is permanent after relaunch.
  - _Requirements: 7.2, 7.3, 7.4, 7.7, 1.2_
  - _Depends on: 8, 19_
  - _Pending device check:_ `HistoryViewModel` (Features/History, `@Observable @MainActor`)
    loads finished rides (`endedAt != nil`) and groups them into `MonthSection`s via a pure,
    unit-tested `static group(rides:calendar:)` — newest month first, rides newest-first, each
    section carrying its ride count + total distance ("4 rides · 18.7 mi") and an uppercased
    "OCTOBER 2026" title from an injected `Calendar`. `delete(_:)` removes permanently via the
    repository and reloads. `HistoryView` (mockup 5) uses a `List` with per-month sections,
    `RideRow(showSpeed: false)`, trailing `swipeActions` Delete behind a confirmation dialog,
    an `onSelectRide` push to `RideSummaryView`, a friendly empty state, and a Synced/Pending/On
    device legend footer; corrupt records are skipped by the repository. Grouping, counts,
    totals, ordering, permanent delete (incl. dropping an emptied section), empty, and
    finished-only are unit-tested in `HistoryViewModelTests`; `build-for-testing` + privacy-check
    pass. Relaunch persistence and the live swipe-to-delete gesture are verified on device by
    the orchestrator.

- [x] 21. Mid-ride persistence safeguard
  - Persist collected points incrementally and/or on background/termination lifecycle events
    so an interrupted ride's data is recoverable.
  - _Verify (device/sim):_ background/relaunch mid-ride; collected points are not lost.
  - _Requirements: 3.6_
  - _Depends on: 8, 10_
  - _Pending device check:_ implemented in `RideSessionViewModel`: incremental snapshots every
    `snapshotEveryPoints` accepted points and every `snapshotEverySeconds` (via `Clock`), plus a
    `persistSnapshot()` the View layer calls on `scenePhase` background. In-progress rides are
    saved through the existing `RideRepository` with `endedAt == nil`; `recoverInterruptedRide()`
    finds one on launch and `finalizeRecoveredRide(_:)` finalizes it. History uses the
    `finishedRides()` helper (filters `endedAt != nil`) so unfinished snapshots never show as
    completed — the `RideRepository` protocol is left unchanged. Unit-tested
    (`RideSessionViewModelTests`); the real background/relaunch flow is verified on device by the
    orchestrator.

- [x] 22. Future-feature seams (abstractions only, no implementation)
  - Define `HazardDetection`, `HazardDetector` (+ `NoopDetector`) and `AlertManager`
    (+ `StubAlertManager`) with the on-device, non-blocking contract documented. Inject the
    no-ops at the composition root. Confirm the MVP never requests camera permission (the Home
    card, the ride-screen "Rear detection off" chip, and the Settings "Soon" row are all inert
    placeholders).
  - Add doc comments pointing the vision/backend teammates to these as their integration
    points, and note `HazardDetection` is shaped to support later near-miss logging.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_
  - _Depends on: 3_
  - _Pending device check:_ abstractions only — `Services/Detection/HazardDetection.swift`
    (`HazardDetection` (Sendable) + `HazardDetector` + `NoopDetector`) and
    `Services/Alerts/AlertManager.swift` (`AlertKind` + `AlertManager` + `StubAlertManager`),
    each with the on-device / non-blocking / never-stops-recording contract documented and
    teammate integration pointers. No AVFoundation, no camera permission anywhere
    (privacy-check passes). Composition-root injection of the no-ops is task 23; the inert UI
    placeholders are tasks 14/16/18.

- [x] 23. Composition root and dependency injection
  - Wire concrete services (`CoreLocationTracker`, `SwiftDataRideRepository`, `SystemClock`,
    `NoopDetector`, `StubAlertManager`) at the App entry inside the `NavigationStack`; feed the
    persisted GPS accuracy into `RideTuning`; present the active ride as a full-screen cover and
    the summary after Stop. Ensure tests still inject fakes.
  - _Verify:_ full build; entire unit suite green; manual end-to-end pass (Home dashboard →
    Start → ride → pause/resume → hold-to-stop → summary → Done → history → delete; Settings
    accuracy + delete-all).
  - _Requirements: all (integration)_
  - _Depends on: 14, 16, 18, 19, 20, 21, 22_
  - _Pending device check:_ `AppEnvironment` (App) is the composition root: `live()` builds a
    `SwiftDataRideRepository` over a `ModelContainer(for: RideRecord.self)` (falling back to an
    in-memory store so the app still launches), plus `CoreLocationTracker`s, `SystemClock`,
    `NoopDetector`, and `StubAlertManager`; `preview(seeded:)` builds the same shape over
    `InMemoryRideRepository` + `FakeLocationTracker` for previews/tests. It exposes
    `homeViewModel`, `settingsViewModel`, `makeHistoryViewModel()`, and `makeRideSession()` —
    the latter copies the persisted `SettingsViewModel.trackingAccuracy` into `RideTuning` so
    the GPS-accuracy setting applies to the next ride (Home and the ride session get separate
    trackers so their single `onAuthorizationChange` callbacks don't clobber each other).
    `WhooshApp` owns a `NavigationStack` rooted at `HomeView`, pushes History/Settings (back
    label "Home") and a history-detail `RideSummaryView`, and presents the ride as a
    non-dismissible `fullScreenCover` whose content is chosen by the pure, unit-tested
    `RideFlowCoordinator` (`.activeRide` while recording/paused/signalLost, `.summary` when
    finished); "Done" clears the session and reloads Home. `scenePhase` leaving `.active` calls
    `persistSnapshot()`, and launch runs `recoverInterruptedRide()` → a "Finish your interrupted
    ride?" alert (Save → `finalizeRecoveredRide`; Discard → delete). Start Ride with
    `notDetermined` location requests When-In-Use then starts (handled inside
    `RideSessionViewModel.start()`). All wiring lives in `App/`; views use only view models and
    `RouteMapView`. `RideFlowCoordinatorTests` cover the cover-presentation logic;
    `build-for-testing` succeeds with no first-party warnings and privacy-check passes. The full
    end-to-end flow and the live full-screen-cover / scenePhase / recovery behavior are verified
    on device by the orchestrator (who also runs the full `xcodebuild test` suite).
  - _Assumption:_ `Ride`/`RoutePoint`/`RideSummary` were made `Hashable` (pure, Foundation-only)
    so the `NavigationStack` path can carry `.summary(Ride)`. A pre-existing non-Sendable
    capture warning in `Support/SystemClock.swift` was fixed minimally (a `@unchecked Sendable`
    box + `MainActor.assumeIsolated`) so the first-party build is warning-clean.

- [x] 24. Resilience pass
  - Verify/implement: permission revoked mid-ride (stop & save), low-power behavior doesn't
    crash, stopped ride releases tracking, user-facing errors are actionable/dismissible and
    don't surface raw framework text.
  - _Requirements: 11.1, 11.2, 11.3, 11.4_
  - _Depends on: 23_
  - _Pending device check:_ code audit-and-fix complete; `build-for-testing` succeeds with
    zero first-party warnings and `scripts/privacy-check.sh` passes (53 files). Audit results:
    **11.1 (revoked mid-ride)** was already correct — `RideSessionViewModel.handleAuthorizationChange`
    row 11 sets `authorizationRevoked`, enters `signalLost`, stops appending, freezes active
    duration, and keeps the ride stoppable/saveable (`permissionRevoked` banner is app copy).
    **11.3 (release tracking / no retain cycles)** was already correct — every tracker/clock
    closure captures `[weak self]`, `stop()` calls `tracker.stopUpdating()` and cancels the
    loss/snapshot timers, and `CoreLocationTracker`'s delegate methods are `nonisolated` and
    hop to the main actor with `[weak self]`. **11.4 (no raw error text)** was already correct —
    `RideBanner` carries only app-written copy; the single `String(describing: error)` is inside
    a `Logger` call in `SwiftDataRideRepository`, never the UI. **11.2 (low-power/thermal)** was
    the real gap and is now **implemented**: new `Services/Power/` seam — `PowerStateMonitoring`
    (protocol, Foundation-only, with an `effectiveAccuracy` policy that degrades `.high` →
    `.balanced` while constrained and never upgrades `.balanced`), `ProcessInfoPowerMonitor`
    (reads `ProcessInfo.isLowPowerModeEnabled` + `thermalState`, observes
    `NSProcessInfoPowerStateDidChange` / `thermalStateDidChangeNotification`), and
    `FakePowerMonitor` for tests. Injected into `RideSessionViewModel` (default
    `ProcessInfoPowerMonitor`): `startMonitoring()` on begin, `stopMonitoring()` on stop, the
    start request uses `currentAccuracy`, and a mid-ride power change re-applies the gentler
    accuracy to the tracker (`isUsingReducedAccuracy` is exposed for the UI). Also: `AppEnvironment`
    now returns a non-fatal `storageNotice` when the SwiftData container can't be created and
    falls back to an in-memory store; `WhooshApp` surfaces it as a calm, dismissible alert.
    Unit tests added (power-degrade at start, mid-ride re-apply, thermal, idle no-op, stop
    releases monitor, plus `PowerStateMonitoringTests`). The real device behaviors — actual Low
    Power Mode / thermal throttling, revoke-mid-ride in Settings, the status-bar tracking
    indicator turning off after stop, and the airplane-mode flow — are verified on device by the
    orchestrator (see `manual-qa.md`).

- [x] 25. Accessibility & privacy compliance pass
  - Accessibility: VoiceOver labels on controls and dynamic metrics/state; the Stop VoiceOver
    custom action works; Dynamic Type spot check on primary screens; state via icon + text, not
    color alone; ≥60pt thumb-zone targets.
  - Privacy: confirm no network calls while sync is off, no analytics/tracking SDKs, honest
    usage strings, no copy claiming collision prediction/prevention (rear-detection placeholders
    framed as experimental), deletion (including delete-all) is real, and no secrets committed.
  - _Verify:_ the full record → summary → history → delete flow works in airplane mode.
  - _Requirements: 10.3, 10.4, 10.5, 10.6, 9.1, 9.2, 9.3, 9.4_
  - _Depends on: 23_
  - _Pending device check:_ code audit-and-fix complete; `build-for-testing` succeeds with zero
    first-party warnings and `scripts/privacy-check.sh` passes (53 files). Audit results:
    **Accessibility** — controls already carry labels (ride metrics use `accessibilityLabel`,
    the Stop control has label "Stop ride, press and hold" plus the `accessibilityAction(named:
    "Stop ride")` custom action, chips/buttons are labeled); the gap was **state announcements**,
    now added — `ActiveRideView` posts `UIAccessibility.post(.announcement, …)` on `banner`
    changes (signal lost / permission revoked) and on pause/resume `rideState` changes. Primary
    ride controls (Pause/Resume pill and `HoldToStopButton`) are ≥60pt (`Theme.Size.minTouchTarget
    = 60`); state is icon + text throughout (`StateChip`). **Privacy** — verified by grep +
    `privacy-check.sh`: no `URLSession`/`URLRequest`/`import Supabase`/analytics imports anywhere
    outside the (not-yet-built) `Services/Sync`; the `NSLocationWhenInUseUsageDescription` and
    `NSCameraUsageDescription` strings in `project.yml` (→ generated Info.plist) **exactly match**
    `privacy.md`; the only `prevent/predict/guarantee` hits are in doc comments explicitly
    disclaiming collision prediction and in honest "experimental · coming soon" UI copy; `delete`
    and `deleteAll` are real deletes on both `InMemoryRideRepository` and `SwiftDataRideRepository`;
    `Config/Secrets.xcconfig` is gitignored (only `Secrets.example.xcconfig` is tracked) and no
    keys appear in source. The on-device confirmations — live VoiceOver walk-through, Dynamic Type
    at Accessibility sizes, the no-camera-prompt behavior, and the full airplane-mode
    record → summary → history → delete flow — are verified on device by the orchestrator (see
    `.kiro/specs/ride-recording-mvp/manual-qa.md`).
  - _Assumption:_ ride-screen metrics intentionally use fixed point sizes (per mockups 2/3, the
    "three numbers" principle) so they stay tabular and never truncate; they don't scale with
    Dynamic Type. This satisfies "SHOULD support Dynamic Type without truncating" (10.4) for the
    ride screen while keeping the glanceable layout; app-chrome screens use system fonts that do
    scale.

---

## Stretch: opt-in Supabase sync (never blocks the demo)

Start only after task 23 is green and Role C has marked the schema "Agreed" in
`.kiro/team/supabase-contract.md`.

- [x] 26. Sync seam and privacy trimming (test-first)
  - Define `SyncStatus`, `RideSyncService`, and `NoopRideSyncService`; add `syncStatus` and
    a pending-delete tombstone to persistence.
  - Implement pure `RoutePrivacy.trim(points:meters:)` (default 160 m each end).
  - Unit tests: trim on normal, short (< 2× trim), empty, and single-point routes; the local
    route stays untouched.
  - _Requirements: 12.2, 12.5_
  - _Depends on: 8, 22_

  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; `scripts/privacy-check.sh` passes (60 files). The full `xcodebuild
    test` run is left to the orchestrator. The existing `SyncStatus` enum (added for the
    summary/history UI) is reused and extended — not duplicated. `syncStatus` (default
    `.localOnly`) was added to the domain `Ride` (new defaulted init parameter, so every
    existing caller is source-compatible) and persisted on `RideRecord` as `syncStatusRaw`
    with a default value for lightweight migration; it maps both ways in
    `SwiftDataRideRepository` and flows through `InMemoryRideRepository` unchanged, so the
    `RideRepository` protocol is **not** altered. `Services/Sync/` now holds `RideSyncService`
    (+ `NoopRideSyncService`), the `PendingRemoteDeleteStore` protocol (+ a
    `UserDefaults`-backed store and an in-memory fake), and the pure `Metrics/RoutePrivacy.swift`
    (`trim(points:meters:)`, default 160 m each end via cumulative Haversine through
    `RideMetrics`; routes ≤ 2× trim return empty; empty/single-point safe; never mutates the
    input). `RoutePrivacyTests` cover normal, short, exactly-2×, empty, single-point, default
    distance, zero-trim, and input-not-mutated. _Assumption:_ "exactly 2× trim" is treated as
    returning empty (no safe interior); a small epsilon keeps that stable against floating-point
    rounding in the Haversine sum.

- [x] 27. SyncCoordinator retry policy (test-first)
  - Implement `SyncCoordinator`: save locally first, then upload; mark `pending` on failure;
    retry pending uploads and deletes on app foreground; idempotent on ride `id`; does
    nothing while sync is disabled. On a prior `deleteAll`, pending remote deletes still
    propagate.
  - Unit tests with a fake `RideSyncService` that fails on command.
  - _Requirements: 12.3, 12.4, 12.6_
  - _Depends on: 26_

  - _Pending device check:_ code + unit tests written and `build-for-testing` succeeds with no
    first-party warnings; `scripts/privacy-check.sh` passes. The full `xcodebuild test` run is
    left to the orchestrator. `Services/Sync/SyncCoordinator.swift` (`@MainActor`) implements
    the retry policy: `rideDidFinish(_:)` uploads the (privacy-trimmed) ride only when
    `service.isEnabled` — success → `.synced`, failure → `.pending`, persisting the status back
    through the `RideRepository` while the local route stays complete; `retryPending()` (app
    foreground) re-uploads every `.pending` ride and drains the tombstone store, never
    re-uploading a `.synced` ride (idempotent on `id`); `rideWasDeleted(_:)` tombstones a
    previously-uploaded ride and calls `deleteRemote`, keeping the tombstone on failure;
    `allRidesWereDeleted(previouslySynced:)` tombstones every previously synced ride; and
    everything is a no-op while sync is disabled. It never touches the ride state machine. The
    scriptable `FakeRideSyncService` (records calls, fails on command) backs
    `SyncCoordinatorTests`, which cover save-locally-before-upload, privacy-trim-on-upload,
    pending-on-failure, retry without duplicates, no re-upload of a synced ride, delete
    propagation after reconnect, deleteAll tombstones (success and failure), and disabled =
    zero calls. The coordinator is **not** wired into the composition root yet (sync is off;
    the Settings toggle stays "Coming soon"); a doc comment on `SyncCoordinator` records exactly
    how task 28 will wire it (`rideDidFinish` after save, `rideWasDeleted` from the delete path,
    `allRidesWereDeleted` from Settings "Delete all rides", `retryPending` on foreground).

- [ ] 28. Supabase implementation and settings toggle enablement
  - Add `supabase-swift` via SPM pinned to an exact version. Implement
    `SupabaseRideSyncService` (anonymous sign-in, upsert into `rides`, delete by id) against
    the agreed contract. Network work runs off the main actor.
  - Enable the previously-disabled Settings sync rows: flip "Sync rides to Whoosh map" from
    "Coming soon" to a working toggle (off by default) with the plain copy on what's uploaded
    and that camera video is never uploaded; activate the "Privacy zone · 0.1 mi" and
    "Identity · Anonymous" rows. Surface sync status (icon + text) in history rows and the
    summary, and show the "Start and end trimmed for privacy" note once a ride is synced.
  - _Verify (device):_ with sync on, a finished ride appears in the Supabase table with a
    trimmed route; another anonymous user can't read it (RLS); airplane mode → pending →
    syncs after reconnect; deleting removes the remote row.
  - _Requirements: 12.1, 12.7, 12.8, 12.9, 12.10, 6.6, 14.5_
  - _Depends on: 14, 27_

---

## Kiro hooks (created, in `.kiro/hooks/`)

Schema: Kiro IDE 1.x `v1` hook JSON. Scripts live in `scripts/`.

- **`run-tests-after-task`** — `PostTaskExec` → `scripts/test.sh` (`xcodebuild test`; skips
  cleanly until task 1 creates `Whoosh.xcodeproj`).
- **`privacy-guard-on-save`** — `PostFileSave` on `\.swift$` → `scripts/privacy-check.sh`:
  network only in `Services/Sync`, no analytics SDKs, no secrets, no collision-prevention
  copy, Models/Metrics Foundation-only, Views don't import CoreLocation/SwiftData, camera
  only in `Services/Detection`.
- **`test-first-before-task`** — `PreTaskExec` agent prompt reminding the agent of the
  test-first, steering-bound working rules for each task.
- Optional later: format/lint on save if the team adopts `swiftformat`/`swiftlint`.

## Definition of done (per task)

1. Code matches the layering table (no illegal imports).
2. New/changed logic has unit tests from the referenced acceptance criteria; suite is green.
3. Device/sim verification done where the task calls for it.
4. No new first-party compiler warnings.
5. Privacy invariants intact (no network unless sync is on, honest copy, no secrets in Git).
