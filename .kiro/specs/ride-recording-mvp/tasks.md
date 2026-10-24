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

- [ ] 2. Design system and theme (Support/)
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

- [ ] 10. RideSessionViewModel state machine (test-first) — core of the MVP
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

- [ ] 11. CoreLocationTracker implementation
  - Implement `CoreLocationTracker` wrapping `CLLocationManager`: map `CLLocation`→`RoutePoint`,
    `CLAuthorizationStatus`→our enum, `didFailWithError`→`LocationFailure`; request
    When-In-Use; apply `TrackingAccuracy` to desiredAccuracy + distanceFilter; `stopUpdating`
    fully releases updates.
  - _Verify (device/sim):_ authorization prompt appears with the honest string; location
    updates flow; stopping ends updates (no leaked tracking).
  - _Requirements: 2.1, 4.1, 11.3_
  - _Depends on: 9_

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

- [ ] 14. Settings screen
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

- [ ] 15. Home screen, permission UX, and location-denied state
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

- [ ] 16. Home dashboard (weekly stats, recent rides, placeholders)
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

- [ ] 17. RouteMapView wrapper
  - Build a single `RouteMapView` that renders a polyline + current-location indicator and
    supports both live (growing) and static (full-route) modes, with reasonable auto-follow
    and manual-pan tolerance. This is the only MapKit touchpoint.
  - _Verify (device/sim):_ a sample polyline renders; auto-follow behaves.
  - _Requirements: 5.1, 5.6_
  - _Depends on: 1_

- [ ] 18. Active ride screen with live map, metrics, and hold-to-stop
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

- [ ] 19. Ride summary screen
  - Build `RideSummaryView` (full-route `RouteMapView` + distance/duration/avg speed via
    formatters) with a sync-status row (icon+text: On device / Pending / Synced), dismissed
    with "Done" after a ride and reused for history detail. (The "trimmed for privacy" note
    appears once sync exists.)
  - _Verify:_ summary shows correct values for a known recorded ride; zero/one-point ride
    renders sensibly; "Done" returns to Home; sync-status shows "On device".
  - _Requirements: 6.1, 6.3, 6.5, 6.6, 10.1, 1.4_
  - _Depends on: 2, 4, 12, 17_

- [ ] 20. History list and deletion
  - Build `HistoryView` + `HistoryViewModel`: rides grouped by month under a header (month ride
    count + total miles), rows showing date/distance/duration and a sync-status indicator
    (icon+text; "On device" until sync exists), swipe-to-delete with a Delete button, tap-
    through to `RideSummaryView`, empty-state, and graceful skip of corrupt records.
  - _Verify (device/sim):_ rides persist across relaunch; month headers show correct counts and
    miles; swipe-to-delete is permanent after relaunch.
  - _Requirements: 7.2, 7.3, 7.4, 7.7, 1.2_
  - _Depends on: 8, 19_

- [ ] 21. Mid-ride persistence safeguard
  - Persist collected points incrementally and/or on background/termination lifecycle events
    so an interrupted ride's data is recoverable.
  - _Verify (device/sim):_ background/relaunch mid-ride; collected points are not lost.
  - _Requirements: 3.6_
  - _Depends on: 8, 10_

- [ ] 22. Future-feature seams (abstractions only, no implementation)
  - Define `HazardDetection`, `HazardDetector` (+ `NoopDetector`) and `AlertManager`
    (+ `StubAlertManager`) with the on-device, non-blocking contract documented. Inject the
    no-ops at the composition root. Confirm the MVP never requests camera permission (the Home
    card, the ride-screen "Rear detection off" chip, and the Settings "Soon" row are all inert
    placeholders).
  - Add doc comments pointing the vision/backend teammates to these as their integration
    points, and note `HazardDetection` is shaped to support later near-miss logging.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_
  - _Depends on: 3_

- [ ] 23. Composition root and dependency injection
  - Wire concrete services (`CoreLocationTracker`, `SwiftDataRideRepository`, `SystemClock`,
    `NoopDetector`, `StubAlertManager`) at the App entry inside the `NavigationStack`; feed the
    persisted GPS accuracy into `RideTuning`; present the active ride as a full-screen cover and
    the summary after Stop. Ensure tests still inject fakes.
  - _Verify:_ full build; entire unit suite green; manual end-to-end pass (Home dashboard →
    Start → ride → pause/resume → hold-to-stop → summary → Done → history → delete; Settings
    accuracy + delete-all).
  - _Requirements: all (integration)_
  - _Depends on: 14, 16, 18, 19, 20, 21, 22_

- [ ] 24. Resilience pass
  - Verify/implement: permission revoked mid-ride (stop & save), low-power behavior doesn't
    crash, stopped ride releases tracking, user-facing errors are actionable/dismissible and
    don't surface raw framework text.
  - _Requirements: 11.1, 11.2, 11.3, 11.4_
  - _Depends on: 23_

- [ ] 25. Accessibility & privacy compliance pass
  - Accessibility: VoiceOver labels on controls and dynamic metrics/state; the Stop VoiceOver
    custom action works; Dynamic Type spot check on primary screens; state via icon + text, not
    color alone; ≥60pt thumb-zone targets.
  - Privacy: confirm no network calls while sync is off, no analytics/tracking SDKs, honest
    usage strings, no copy claiming collision prediction/prevention (rear-detection placeholders
    framed as experimental), deletion (including delete-all) is real, and no secrets committed.
  - _Verify:_ the full record → summary → history → delete flow works in airplane mode.
  - _Requirements: 10.3, 10.4, 10.5, 10.6, 9.1, 9.2, 9.3, 9.4_
  - _Depends on: 23_

---

## Stretch: opt-in Supabase sync (never blocks the demo)

Start only after task 23 is green and Role C has marked the schema "Agreed" in
`.kiro/team/supabase-contract.md`.

- [ ] 26. Sync seam and privacy trimming (test-first)
  - Define `SyncStatus`, `RideSyncService`, and `NoopRideSyncService`; add `syncStatus` and
    a pending-delete tombstone to persistence.
  - Implement pure `RoutePrivacy.trim(points:meters:)` (default 160 m each end).
  - Unit tests: trim on normal, short (< 2× trim), empty, and single-point routes; the local
    route stays untouched.
  - _Requirements: 12.2, 12.5_
  - _Depends on: 8, 22_

- [ ] 27. SyncCoordinator retry policy (test-first)
  - Implement `SyncCoordinator`: save locally first, then upload; mark `pending` on failure;
    retry pending uploads and deletes on app foreground; idempotent on ride `id`; does
    nothing while sync is disabled. On a prior `deleteAll`, pending remote deletes still
    propagate.
  - Unit tests with a fake `RideSyncService` that fails on command.
  - _Requirements: 12.3, 12.4, 12.6_
  - _Depends on: 26_

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
