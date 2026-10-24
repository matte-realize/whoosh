# Implementation Plan — Whoosh Ride Recording MVP (iOS)

Small, ordered, verifiable tasks for the **iOS app owner**. Each task builds on the previous.
Run the unit test suite before marking a task done. Tasks that touch real Core Location /
MapKit also require a brief manual device/simulator check, called out explicitly.

This plan covers only the iOS ride-recording MVP. Cross-team ownership (vision, backend/data)
lives in `../../team/team-plan.md`. The future-seam tasks here (13) are what the vision and
alert work will plug into.

Do not begin implementation until the spec is reviewed and approved.

Conventions:
- `(test-first)` means write failing unit tests from the referenced acceptance criteria,
  then implement until green.
- `_Requirements:_` maps the task to acceptance criteria in `requirements.md`.
- `_Depends on:_` lists prerequisite task numbers.
- Each task is intended to be a single reviewable commit (or a small PR).

---

- [ ] 1. Project scaffolding and app foundation
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

- [ ] 2. Domain models (pure)
  - Implement `RoutePoint`, `RideSummary`, `Ride`, `RideState`, and the `RideTuning` config
    struct with documented defaults.
  - Ensure Models import Foundation only (no SwiftUI/CoreLocation/SwiftData/MapKit), per the
    layering table.
  - _Verify:_ models compile in the test target and are `Equatable`/`Codable` where specified.
  - _Requirements: 3.5, 4.2, 4.3_

- [ ] 3. Ride metrics (pure, test-first)
  - Implement `RideMetrics.distanceMeters`, `averageSpeed`, and `summary`.
  - Unit tests: empty → zeros; single point → zero distance; two points → known distance
    within tolerance; a multi-point fixture with a hand-computed expected distance; duration
    0 → average speed 0 (no NaN/divide-by-zero).
  - _Requirements: 6.2, 6.3, 6.4_
  - _Depends on: 2_

- [ ] 4. Clock seam (test-first)
  - Define the `Clock` protocol with `SystemClock` and `TestClock` (manual time advance +
    deterministic scheduled-work firing).
  - Unit tests: scheduled work fires after advancing past the interval; cancellation works.
  - _Requirements: 4.6 (testable timing foundation)_

- [ ] 5. RideRepository protocol + in-memory fake (test-first)
  - Define `RideRepository` and `InMemoryRideRepository`.
  - Unit tests: save; `allRides` returns most-recent-first; `ride(id:)` hit/miss; `delete`
    removes permanently; deleting a missing id is a safe no-op.
  - _Requirements: 7.5, 7.2, 7.4_
  - _Depends on: 2_

- [ ] 6. SwiftData persistence implementation (test-first)
  - Define `RideRecord` `@Model` (points stored as an encoded blob) and
    `SwiftDataRideRepository` with `Ride` ↔ `RideRecord` mapping.
  - Wrap point decoding so a corrupt record is skipped (logged), not thrown.
  - Unit tests against an in-memory SwiftData container: save/list/get/delete; most-recent-
    first ordering; permanence across container reload; corrupt-record skip.
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.6, 7.7_
  - _Depends on: 2, 5_

- [ ] 7. LocationTracking protocol + fake (test-first)
  - Define `LocationTracking`, `LocationAuthorizationStatus`, `TrackingAccuracy`,
    `LocationFailure`, and `FakeLocationTracker` that scripts points, status changes, and
    failures on command.
  - Unit tests: fake delivers scripted callbacks in order; authorization change propagates.
  - _Requirements: 2.1, 4.1, 4.6_
  - _Depends on: 2_

- [ ] 8. RideSessionViewModel state machine (test-first) — core of the MVP
  - Implement the `@Observable` view model owning `RideState`, injected `LocationTracking`,
    `Clock`, and `RideTuning`. Handle start/pause/resume/stop, acceptable-fix filtering
    (accuracy + plausible-speed/jump), the signal-loss timer, authorization-revoked-mid-ride,
    active-duration accumulation (excluding pauses), and finalize→compute→persist.
  - Unit tests: all 14 transition-table rows from the design, plus active-duration excludes
    paused spans, undefined transitions are no-ops, and finalize with zero points yields a
    zeroed summary.
  - _Requirements: 3.1–3.8, 4.1–4.7, 2.4, 11.1, 11.3_
  - _Depends on: 3, 4, 5, 7_

- [ ] 9. CoreLocationTracker implementation
  - Implement `CoreLocationTracker` wrapping `CLLocationManager`: map `CLLocation`→`RoutePoint`,
    `CLAuthorizationStatus`→our enum, `didFailWithError`→`LocationFailure`; request
    When-In-Use; apply `TrackingAccuracy` to desiredAccuracy + distanceFilter; `stopUpdating`
    fully releases updates.
  - _Verify (device/sim):_ authorization prompt appears with the honest string; location
    updates flow; stopping ends updates (no leaked tracking).
  - _Requirements: 2.1, 4.1, 11.3_
  - _Depends on: 7_

- [ ] 10. Formatters and unit policy (test-first)
  - Centralize formatting in US customary units: miles (2 decimals under 10 mi, 1 above),
    mph (1 decimal), feet for short distances; duration `m:ss` under an hour, `h:mm:ss` above.
    Conversion from SI happens only here.
  - Unit tests (parameterized): zero, typical, and large values; the 10-mile and 1-hour
    boundaries.
  - _Requirements: 10.1, 10.2_
  - _Depends on: 2_

- [ ] 11. Home screen and permission UX
  - Build `HomeView`: primary Start Ride, history entry, empty-state. Large one-handed
    targets. Wire permission-denied/restricted explanation with an Open-Settings deep link;
    keep history reachable when denied; reflect live authorization changes; handle
    services-disabled with the same path.
  - Accessibility labels on controls; state not conveyed by color alone.
  - _Verify (device/sim):_ deny path shows explanation and opens Settings; history still opens.
  - _Requirements: 1.1, 1.2, 1.6, 2.2, 2.3, 2.4, 2.6, 10.3, 10.5_
  - _Depends on: 8, 9_

- [ ] 12. RouteMapView wrapper
  - Build a single `RouteMapView` that renders a polyline + current-location indicator and
    supports both live (growing) and static (full-route) modes, with reasonable auto-follow
    and manual-pan tolerance. This is the only MapKit touchpoint.
  - _Verify (device/sim):_ a sample polyline renders; auto-follow behaves.
  - _Requirements: 5.1, 5.5_
  - _Depends on: 1_

- [ ] 13. Active ride screen with live map and metrics
  - Build `ActiveRideView` using `RouteMapView`: live route, live elapsed/distance via
    formatters, pause/resume/stop controls, and an icon+text state banner
    (recording/paused/signal-lost). Keep metric updates off the main-thread hot path.
  - _Verify (device/sim):_ route draws live on a short walk; pause/resume/stop behave;
    signal-lost banner appears when updates stall (can simulate via tracker).
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.6, 3.2, 3.3, 3.4, 10.3, 10.5_
  - _Depends on: 8, 10, 12_

- [ ] 14. Ride summary screen
  - Build `RideSummaryView` (full-route `RouteMapView` + distance/duration/avg speed via
    formatters), reused for a just-finished ride and for a history detail.
  - _Verify:_ summary shows correct values for a known recorded ride; zero/one-point ride
    renders sensibly.
  - _Requirements: 6.1, 6.3, 6.5, 10.1_
  - _Depends on: 3, 10, 12_

- [ ] 15. History list and deletion
  - Build `HistoryView` + `HistoryViewModel`: most-recent-first rows (date/distance/duration),
    swipe-to-delete with confirmation, tap-through to `RideSummaryView`, empty-state, and
    graceful skip of corrupt records.
  - _Verify (device/sim):_ rides persist across relaunch; deletion is permanent after relaunch.
  - _Requirements: 7.2, 7.3, 7.4, 7.7, 1.2_
  - _Depends on: 6, 14_

- [ ] 16. Mid-ride persistence safeguard
  - Persist collected points incrementally and/or on background/termination lifecycle events
    so an interrupted ride's data is recoverable.
  - _Verify (device/sim):_ background/relaunch mid-ride; collected points are not lost.
  - _Requirements: 3.6_
  - _Depends on: 6, 8_

- [ ] 17. Future-feature seams (abstractions only, no implementation)
  - Define `HazardDetection`, `HazardDetector` (+ `NoopDetector`) and `AlertManager`
    (+ `StubAlertManager`) with the on-device, non-blocking contract documented. Inject the
    no-ops at the composition root. Confirm the MVP never requests camera permission.
  - Add doc comments pointing the vision/backend teammates to these as their integration
    points, and note `HazardDetection` is shaped to support later near-miss logging.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  - _Depends on: 2_

- [ ] 18. Composition root and dependency injection
  - Wire concrete services (`CoreLocationTracker`, `SwiftDataRideRepository`, `SystemClock`,
    `NoopDetector`, `StubAlertManager`) at the App entry; ensure tests still inject fakes.
  - _Verify:_ full build; entire unit suite green; manual end-to-end pass (start → ride →
    pause/resume → stop → summary → history → delete).
  - _Requirements: all (integration)_
  - _Depends on: 11, 13, 14, 15, 16, 17_

- [ ] 19. Resilience pass
  - Verify/implement: permission revoked mid-ride (stop & save), low-power behavior doesn't
    crash, stopped ride releases tracking, user-facing errors are actionable/dismissible and
    don't surface raw framework text.
  - _Requirements: 11.1, 11.2, 11.3, 11.4_
  - _Depends on: 18_

- [ ] 20. Accessibility & privacy compliance pass
  - Accessibility: VoiceOver labels on controls and dynamic metrics/state; Dynamic Type spot
    check on primary screens; state not color-only.
  - Privacy: confirm no network calls while sync is off, no analytics/tracking SDKs, honest
    usage strings, no copy claiming collision prediction/prevention, deletion is real, and no
    secrets committed.
  - _Verify:_ the full record → summary → history → delete flow works in airplane mode.
  - _Requirements: 10.3, 10.4, 10.5, 9.1, 9.2, 9.3, 9.4_
  - _Depends on: 18_

---

## Stretch: opt-in Supabase sync (never blocks the demo)

Start only after task 18 is green and Role C has marked the schema "Agreed" in
`.kiro/team/supabase-contract.md`.

- [ ] 21. Sync seam and privacy trimming (test-first)
  - Define `SyncStatus`, `RideSyncService`, and `NoopRideSyncService`; add `syncStatus` and
    a pending-delete tombstone to persistence.
  - Implement pure `RoutePrivacy.trim(points:meters:)` (default 160 m each end).
  - Unit tests: trim on normal, short (< 2× trim), empty, and single-point routes; the local
    route stays untouched.
  - _Requirements: 12.2, 12.5_
  - _Depends on: 6, 17_

- [ ] 22. SyncCoordinator retry policy (test-first)
  - Implement `SyncCoordinator`: save locally first, then upload; mark `pending` on failure;
    retry pending uploads and deletes on app foreground; idempotent on ride `id`; does
    nothing while sync is disabled.
  - Unit tests with a fake `RideSyncService` that fails on command.
  - _Requirements: 12.3, 12.4, 12.6_
  - _Depends on: 21_

- [ ] 23. Supabase implementation and settings toggle
  - Add `supabase-swift` via SPM pinned to an exact version. Implement
    `SupabaseRideSyncService` (anonymous sign-in, upsert into `rides`, delete by id) against
    the agreed contract. Network work runs off the main actor.
  - Add a Settings screen with the sync toggle (off by default) and plain copy describing
    what's uploaded. Show sync status icon + text in history rows.
  - _Verify (device):_ with sync on, a finished ride appears in the Supabase table with a
    trimmed route; another anonymous user can't read it (RLS); airplane mode → pending →
    syncs after reconnect; deleting removes the remote row.
  - _Requirements: 12.1, 12.7, 12.8, 12.9, 12.10_
  - _Depends on: 22_

---

## Suggested Kiro hooks (create after task 1)

- **Run tests after each spec task** — `PostTaskExec` → `xcodebuild test` (or `swift test`),
  enforcing the test-first flow.
- **Privacy guard on writes** — `PreToolUse` on write tools (agent action) checking new code
  against the privacy steering (network only via `RideSyncService`, no tracking SDKs, no
  secrets, honest copy).
- **Format/lint on save** — `PostFileSave` matching `\.swift$` → `swiftformat`/`swiftlint`
  if the team adopts them.

## Definition of done (per task)

1. Code matches the layering table (no illegal imports).
2. New/changed logic has unit tests from the referenced acceptance criteria; suite is green.
3. Device/sim verification done where the task calls for it.
4. No new first-party compiler warnings.
5. Privacy invariants intact (no network unless sync is on, honest copy, no secrets in Git).
