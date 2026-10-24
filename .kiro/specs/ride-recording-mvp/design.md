# Design — Whoosh Ride Recording MVP

## Overview

This design implements the ride-recording MVP with an MVVM + service-layer architecture.
The guiding constraints: UI is thin and declarative, all framework access (Core Location,
persistence) sits behind protocols, ride lifecycle is an explicit state machine, and the
future camera/alert subsystems exist only as protocol seams. Everything demo-critical runs
on-device with no network.

The UI realizes the reviewed mockups (`design/mockups/whoosh-mvp-mockups-v0.1.svg`, 7 screens):
a `NavigationStack` with **Home** as the hub (a weekly-stats dashboard), **History** and
**Settings** pushed from Home, the **active ride** as a non-dismissible full-screen cover, the
**ride summary** shown after Stop and dismissed with "Done", and the **location-denied** Home
state. A shared `Theme` and component set (Requirement 15) keep screens consistent: light
chrome, dark ride screen. Stop is a press-and-hold; Pause/Resume are taps.

Target: iOS 17+, Xcode 26.5 / Swift 6 toolchain, SwiftUI, MapKit, Core Location, SwiftData,
optional Supabase sync. Primary demo device: iPhone 14.

### Revisability note (read this first)

The framework and library choices below (SwiftData, MapKit, the Observation framework, the
test framework) are **recommended defaults chosen for hackathon velocity**, not hard
mandates. Because every framework touchpoint sits behind a protocol, any of them can be
swapped with localized change:

- Persistence engine is behind `RideRepository` — SwiftData can become Core Data or
  Codable-to-disk without touching view models.
- Location is behind `LocationTracking` — the engine never imports Core Location.
- Map rendering is isolated in a small set of views — MapKit could be replaced by another
  renderer by rewriting those views only.

Where a decision is genuinely open, this document lists the alternative and the trade-off.
Treat this as a living document: update it when the team picks a different path.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                            SwiftUI Views                             │
│  HomeView · ActiveRideView · RideSummaryView · HistoryView ·         │
│  SettingsView     (inside a NavigationStack; ActiveRideView is a      │
│                    non-dismissible full-screen cover)                │
│                 ── all styled via Theme + shared components ──        │
└───────────────┬──────────────────────────────────────────────────────┘
                │ observe state / send intents
┌───────────────▼──────────────────────────────────────────────────────┐
│                        ViewModels (@Observable)                        │
│  HomeViewModel · RideSessionViewModel · HistoryViewModel ·             │
│  SummaryVM · SettingsViewModel                                         │
└───────┬───────────────────────┬───────────────┬─────────────┬─────────┘
        │                       │               │             │
┌───────▼────────┐   ┌──────────▼───────┐  ┌─────▼──────────┐ │
│ LocationTracking│   │  RideRepository  │  │  HazardDetector/│ │
│   (protocol)    │   │   (protocol)     │  │  AlertManager   │ │
│                 │   │  save/all/get/   │  │  (future seams) │ │
│ CoreLocation-   │   │  delete/deleteAll│  │ NoopDetector /  │ │
│ Tracker · Fake  │   │ SwiftData · Fake │  │ StubAlertManager│ │
└─────────────────┘   └──────────────────┘  └─────────────────┘ │
        │                       │                                │
   ┌────▼─────┐           ┌─────▼──────┐                 ┌───────▼───────┐
   │  Clock   │           │ Domain<->  │                 │ WeeklyStats   │
   │ (protocol│           │ Record map │                 │ (pure, in     │
   │ for tests)│          └────────────┘                 │ Metrics)      │
   └──────────┘                                           └───────────────┘
```

`Theme` and shared components live in `Support/` and are imported only by Views.
`SettingsViewModel` reads/writes GPS accuracy in `UserDefaults` and drives `RideTuning`.

Dependency rule: Views depend on view models; view models depend on service *protocols* and
a `Clock` protocol; concrete implementations are injected at the composition root (the App).
Tests inject fakes and a controllable clock. The ride engine never imports Core Location,
SwiftData, or MapKit.

## Layering and module boundaries

| Layer        | Knows about                        | Must NOT import                         |
| ------------ | ---------------------------------- | --------------------------------------- |
| Models       | Foundation only                    | SwiftUI, CoreLocation, SwiftData, MapKit|
| Metrics      | Models, Foundation                 | anything UI or framework-specific       |
| Services     | Models + their own framework       | SwiftUI, other services' concrete types |
| ViewModels   | Models, Metrics, service protocols | concrete services, SwiftUI views        |
| Views        | ViewModels, SwiftUI, MapKit        | Core Location, SwiftData directly       |
| Composition  | everything (wires it together)     | —                                       |

This table is the enforceable version of "testable components." If a type needs an import it
shouldn't have per this table, that's a design smell.

`WeeklyStats` lives in the **Metrics** layer (Models + Foundation only). `Theme` and the shared
components live in `Support/` and are imported only by Views and the composition root.

## Navigation structure

The app is a single `NavigationStack` rooted at Home. The mockups map to this shape:

```
NavigationStack (root = HomeView)
├── push → HistoryView          (back label "Home")
│     └── push → RideSummaryView (history detail; reused component)
├── push → SettingsView         (back label "Home")
└── fullScreenCover → ActiveRideView   (interactiveDismissDisabled; no swipe-away)
      └── on Stop(hold) → sheet/cover → RideSummaryView
            └── "Done" dismisses back to Home
```

Rules:

- **Home is the hub.** The weekly-stats dashboard, Recent rides ("See all" → History), the
  rear-detection placeholder card, the Start Ride button, and the "GPS ready" chip all live
  here (Requirement 13). In the location-denied state Home swaps the dashboard for the denied
  view (explanation, numbered Open-Settings help, Open Settings + View past rides buttons,
  Requirement 2).
- **Active ride is a non-dismissible full-screen cover** (`fullScreenCover` +
  `interactiveDismissDisabled`) so a swipe can't abandon a ride. The only exit is the press-
  and-hold Stop (or its VoiceOver custom action).
- **Summary after Stop** is presented over the (now-dismissed) cover and dismissed with an
  explicit "Done" that returns to Home. The same `RideSummaryView` is pushed for history
  detail.
- History and Settings are pushes with a "Home" back label.

## Domain Models

Plain value types, framework-free, so they're trivially testable.

```swift
struct RoutePoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speedMetersPerSecond: Double   // < 0 when unknown
    let horizontalAccuracyMeters: Double
}

struct RideSummary: Equatable, Codable {
    let distanceMeters: Double
    let activeDuration: TimeInterval   // excludes paused intervals
    let averageSpeedMetersPerSecond: Double
}

struct Ride: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var points: [RoutePoint]
    var summary: RideSummary           // recomputed on finalize
}

enum RideState: Equatable {
    case idle
    case recording
    case paused
    case signalLost        // was recording, acceptable updates stalled
    case finished
}
```

Rationale for keeping a domain `Ride` separate from the persisted record: the view models and
metrics operate on value types that are cheap to construct in tests, and storage concerns
(SwiftData model identity, relationships, migration) never leak upward. Mapping happens at the
repository boundary only.

### Active duration definition (Requirement 3.8)

Active duration is the sum of time spent in `recording`/`signalLost`, excluding `paused`
spans. The view model tracks it by accumulating `now - lastResumeTimestamp` on each pause and
on finalize, rather than `endedAt - startedAt`. This is a pure accumulation that is
unit-tested with a fake clock.

## Service Protocols

### Clock (test seam for time)

Time is a dependency, so signal-loss timeouts and durations are testable without waiting in
real time.

```swift
protocol Clock {
    func now() -> Date
    // schedules work after an interval; cancellable
    func schedule(after: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
}
```

- `SystemClock` wraps `Date()` + a timer.
- `TestClock` lets tests advance time manually and fire scheduled work deterministically.

### LocationTracking

Abstracts Core Location so the ride engine is testable with injected fixtures.

```swift
protocol LocationTracking: AnyObject {
    var authorizationStatus: LocationAuthorizationStatus { get }
    var onAuthorizationChange: ((LocationAuthorizationStatus) -> Void)? { get set }
    var onLocation: ((RoutePoint) -> Void)? { get set }
    var onFailure: ((LocationFailure) -> Void)? { get set }

    func requestWhenInUseAuthorization()
    func startUpdating(accuracy: TrackingAccuracy)
    func stopUpdating()
}

enum LocationAuthorizationStatus {
    case notDetermined, denied, restricted, authorizedWhenInUse, authorizedAlways
}

enum TrackingAccuracy {
    case balanced   // ~ kCLLocationAccuracyNearestTenMeters, larger distanceFilter
    case high       // ~ kCLLocationAccuracyBest, small distanceFilter
}

enum LocationFailure { case denied, servicesDisabled, unknown(String) }
```

- `CoreLocationTracker` wraps `CLLocationManager`, maps `CLLocation` → `RoutePoint`, maps
  `CLAuthorizationStatus` → our enum, and funnels `didFailWithError` into `onFailure`.
- `FakeLocationTracker` emits scripted points, status changes, and failures on command.

**Why callbacks over an `AsyncStream`:** either works; callbacks keep the fake trivial and
avoid task-lifetime questions in a hackathon. An `AsyncStream`-based variant is a valid
alternative if the team prefers structured concurrency — the protocol can expose a stream
instead without affecting the engine's logic shape.

### RideRepository

```swift
protocol RideRepository {
    func save(_ ride: Ride) throws
    func allRides() throws -> [Ride]          // most recent first
    func ride(id: UUID) throws -> Ride?
    func delete(id: UUID) throws
    func deleteAll() throws                   // real, permanent wipe of all rides
}
```

- `SwiftDataRideRepository` maps `Ride` ↔ `RideRecord` (the `@Model`).
- `InMemoryRideRepository` (fake) backs unit tests and SwiftUI previews.
- `deleteAll()` is a real, permanent deletion of every stored ride (Requirement 7.8). It is
  implemented on both the fake and the SwiftData repository and is invoked from the Settings
  "Delete all rides" destructive action behind a confirmation alert. If synced rides existed,
  remote deletion is requested later once sync exists (`SyncCoordinator`, Requirement 12.6).

**Storage of points:** the recommended default encodes the `[RoutePoint]` array as a `Data`
blob (JSON or a compact binary) on the record, rather than modeling each point as its own
`@Model` row. Rationale: a ride can have thousands of points; a blob avoids thousands of rows
and relationship overhead, and the repository is the only place that knows. The alternative
(a child `@Model` for points) is fine if the team later needs to query individual points;
switching is localized to the repository.

### Persisted record (SwiftData default)

```swift
@Model
final class RideRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double       // denormalized summary for fast list rows
    var activeDuration: TimeInterval
    var averageSpeed: Double
    var encodedPoints: Data          // encoded [RoutePoint]

    init(/* ... */) { /* ... */ }
}
```

Corrupt-record handling (Requirement 7.7): decoding `encodedPoints` is wrapped so a single
bad record is skipped (logged) rather than throwing out of `allRides()`.

### RideSyncService (opt-in Supabase sync, Requirement 12)

```swift
enum SyncStatus: String, Codable { case localOnly, pending, synced }

protocol RideSyncService {
    var isEnabled: Bool { get }
    func upload(_ ride: Ride) async throws          // idempotent upsert on ride.id
    func deleteRemote(id: UUID) async throws
}
```

- `NoopRideSyncService` is the MVP default (`isEnabled == false`, does nothing).
- `SupabaseRideSyncService` (later) uses the pinned `supabase-swift` client, anonymous
  sign-in, and an upsert into the `rides` table defined in `.kiro/team/supabase-contract.md`.
  Network calls run off the main actor.
- A small `SyncCoordinator` owns the retry policy: after a ride is saved locally it calls
  `upload`; on failure it marks the record `pending`; on app foreground it retries pending
  records and pending deletes. It never touches the ride state machine.
- `RoutePrivacy.trim(points:meters:)` is a pure function applied before upload (default
  160 m from each end). It is unit-tested, including routes shorter than twice the trim.
- `RideRecord` gains `syncStatus: SyncStatus` (default `.localOnly`) and a
  `pendingRemoteDelete` tombstone list lives alongside it so offline deletes still propagate.

Why local-first instead of using Supabase as the store: the demo has to survive bad venue
Wi-Fi, the ride engine stays network-free and easy to test, and the web dashboard only needs
finished rides.

### Future seams (defined, not implemented)

```swift
// A detection event the detector emits; shaped to also support future near-miss logging.
struct HazardDetection {
    let timestamp: Date
    let kind: String                 // kept open (e.g., "vehicle"); not an enum yet
    let confidence: Double
    let relativePositionHint: String?  // left/center/right or similar, optional
}

protocol HazardDetector {
    // Pushes detections as they occur. Implementation runs on-device.
    var onDetection: ((HazardDetection) -> Void)? { get set }
    func start()
    func stop()
}

enum AlertKind { case cautionRearVehicle }   // open to grow

protocol AlertManager {
    // Haptic/audio alert. MUST never block or stop ride recording.
    func fire(_ kind: AlertKind)
}
```

- MVP ships `NoopDetector` (emits nothing) and `StubAlertManager` (does nothing).
- Contract documented: on-device, non-blocking, must not throttle the ride engine.
- Concurrency: the project uses main-actor default isolation, so the detector's frame
  processing and inference must be explicitly moved off the main actor (a dedicated actor or
  `@concurrent` work). Only `onDetection` delivery hops back to the main actor.
  `HazardDetection` must be `Sendable`.
- `HazardDetection` deliberately avoids locking the vision team into an enum of classes or a
  specific geometry; it carries enough to later tie a detection to a `RoutePoint` for
  near-miss logging (Requirement 8.6) without a redesign.

## Ride Session State Machine

The core recording logic lives in `RideSessionViewModel`, which owns a `RideState` and reacts
to user intents, location events, and clock events.

```
                 start (authorized)
   idle ───────────────────────────────▶ recording
     ▲                                     │   ▲
     │ stop(finalize)                      │   │ resume
     │                                pause│   │
 finished ◀───── stop ──── paused ◀────────┘   │
     ▲                                          │
     │                          updates stall   │ updates resume
     └────── stop ───── signalLost ◀────────────┘
                           (from recording)
```

Full transition table (every row is a unit test driven by `FakeLocationTracker` + `TestClock`):

| #  | From        | Event                                   | Guard                     | To           | Effect                                              |
| -- | ----------- | --------------------------------------- | ------------------------- | ------------ | --------------------------------------------------- |
| 1  | idle        | start                                   | authorized                | recording    | new ride, startedAt, startUpdating, arm loss-timer  |
| 2  | idle        | start                                   | not authorized            | idle         | request auth or show explanation (no ride created)  |
| 3  | recording   | location point                          | acceptable fix            | recording    | append point, update live metrics, re-arm loss-timer|
| 4  | recording   | location point                          | unacceptable (accuracy/jump)| recording  | discard point, re-arm loss-timer                    |
| 5  | recording   | pause                                   | —                         | paused       | stop appending, accumulate active duration          |
| 6  | paused      | resume                                  | —                         | recording    | set lastResume, re-arm loss-timer                   |
| 7  | paused      | location point                          | —                         | paused       | ignore (no append)                                  |
| 8  | recording   | loss-timer fires (no fix in interval)   | —                         | signalLost   | surface banner; keep ride; keep updates requested   |
| 9  | signalLost  | location point                          | acceptable fix            | recording    | clear banner, append, re-arm loss-timer             |
| 10 | signalLost  | pause                                   | —                         | paused       | stop appending                                      |
| 11 | recording   | authorization revoked                   | —                         | signalLost*  | stop appending; surface; allow stop (Req 11.1)      |
| 12 | any active  | stop                                    | —                         | finished     | stopUpdating, finalize duration, compute+persist    |
| 13 | finished    | any                                     | —                         | finished     | no-op (terminal)                                    |
| 14 | idle        | pause/resume/stop                       | —                         | idle         | no-op (undefined transitions are safe no-ops, Req 3.5)|

\*Row 11: revoked authorization is modeled as a terminal-ish signal loss the user can stop
and save; we do not silently discard the ride.

Configurable constants (one `RideTuning` struct, Requirement 4.2/4.3/4.4):

```swift
struct RideTuning {
    var maxAcceptableAccuracyMeters: Double = 30
    var signalLossTimeout: TimeInterval = 8
    var maxPlausibleSpeedMetersPerSecond: Double = 35   // ~78 mph sanity cap
    var accuracy: TrackingAccuracy = .high
    // Point cap policy (Req 4.7): nil = no cap for MVP (documented decision).
    var maxStoredPoints: Int? = nil
}
```

## Metric Computation (pure functions)

Framework-free `RideMetrics`, the testable heart of Requirement 6:

```swift
enum RideMetrics {
    static func distanceMeters(_ points: [RoutePoint]) -> Double  // sum of Haversine segments
    static func averageSpeed(distanceMeters: Double, activeDuration: TimeInterval) -> Double
    static func summary(points: [RoutePoint], activeDuration: TimeInterval) -> RideSummary
}
```

- Distance uses the Haversine formula per consecutive accepted-point pair.
- Edge cases: empty → all zeros; single point → zero distance; duration 0 → average speed 0
  (no divide-by-zero).
- Note: active duration is supplied by the view model (it knows pause spans); metrics do not
  infer it from timestamps, so paused gaps don't inflate it.

### WeeklyStats (pure, powers the Home dashboard — Requirement 13)

A second framework-free function in the Metrics layer aggregates finished rides into the
current week's dashboard numbers. It takes the calendar and "now" as inputs so it is fully
deterministic and testable (no hidden `Date()` or `Calendar.current`).

```swift
struct WeeklyStats: Equatable {
    let totalDistanceMeters: Double
    let rideCount: Int
    let totalActiveDuration: TimeInterval
    // Monday…Sunday, index 0 = Monday; distance in meters per weekday.
    let distancePerWeekday: [Double]   // always length 7
}

enum WeeklyStatsCalculator {
    static func compute(rides: [Ride], now: Date, calendar: Calendar) -> WeeklyStats
}
```

- The current week is `[startOfWeek, startOfWeek + 7 days)` derived from `calendar` and `now`;
  the bar chart buckets each ride's `startedAt` into its weekday (Mon→Sun).
- Rides outside the current week are ignored; rides exactly on the week start are included and
  on the week end (next week start) are excluded (half-open interval).
- Distance per ride comes from the ride's finalized summary; zero-distance rides still count
  toward `rideCount` and their weekday bucket (with 0 distance).
- Because the calendar is injected, DST transitions are handled by `Calendar` date math rather
  than by assuming 24-hour days.
- Edge cases unit-tested (test-first): no rides; rides outside the current week; rides on the
  week start/end boundaries; a week spanning a DST change; zero-distance rides.

## UI Layer

All views are driven by `@Observable` view models; no framework objects are constructed
inside views. Everything is styled through the shared `Theme` and components (below).

- **HomeView** (`HomeViewModel`) — the hub and dashboard (Requirement 13). Shows the Whoosh
  wordmark, "Ready to ride?", a This-Week stats card (total miles, ride count, total active
  time, and a Mon–Sun 7-bar chart fed by `WeeklyStatsCalculator.compute`), a Recent rides list
  (latest 2–3 + "See all" → History), a "Rear vehicle detection — Experimental, coming soon"
  placeholder card, a prominent Start Ride button, and a "GPS ready" status chip. When auth is
  denied/restricted/services-off it swaps the dashboard for the **location-denied** view:
  explanation, a numbered Open-Settings help (1. Open Settings, 2. tap Location, 3. choose
  "While Using the App"), an Open-Settings deep link, and a "View past rides" button
  (Requirement 2). `HomeViewModel` loads rides via `RideRepository`, computes `WeeklyStats`
  with an injected `Clock`/`Calendar`, and exposes auth status. Large one-handed targets ≥60pt.
- **ActiveRideView** (`RideSessionViewModel`) — presented as a non-dismissible full-screen
  cover. Dark theme. MapKit `Map` with a `MapPolyline` of collected points + user-location
  indicator; at most three numbers (ride time large, distance, speed); a state chip
  (Recording/Paused, icon+text) and a non-functional "Rear detection off" chip; a press-and-
  hold **Stop** control with visible hold progress (~1s) plus a VoiceOver "Stop ride" custom
  action; tap Pause/Resume. Signal-lost shows the amber banner "GPS signal lost — Your ride
  continues. Resuming...". Paused reuses the same layout. State is icon+text, never color
  alone (Req 5, 10.5). Auto-follows with manual-pan tolerance (Req 5.6). Metric updates stay
  off the main-thread hot path.
- **RideSummaryView** (`SummaryVM`) — full-route map + distance/duration/avg speed; a sync-
  status row (icon+text: On device / Pending / Synced) and, once sync exists and the ride is
  synced, the "Start and end trimmed for privacy" note. Dismissed with "Done" after a ride;
  reused as history detail (Req 6.5/6.6).
- **HistoryView** (`HistoryViewModel`) — rides most-recent-first grouped by month, each month
  under a header showing the month's ride count and total miles. Rows show date/distance/
  duration plus a sync-status indicator (icon+text; "On device" until sync exists). Swipe-to-
  delete reveals a Delete button; tap-through to `RideSummaryView`; empty-state; graceful skip
  of corrupt records (Req 7).
- **SettingsView** (`SettingsViewModel`) — pushed from Home (back "Home"). Rows: **GPS
  accuracy** (Balanced / High) persisted in `UserDefaults` and fed into `RideTuning.accuracy`
  (functional); **Units** read-only "Miles · mph"; **Delete all rides** (destructive) → confirm
  alert → `RideRepository.deleteAll()`. Disabled-with-"Coming soon" until sync ships: a "Sync
  rides to Whoosh map" toggle (plain copy on what's uploaded + that camera video is never
  uploaded), "Privacy zone · 0.1 mi", and "Identity · Anonymous"; plus a disabled "Rear
  vehicle detection · Soon" row (experimental, no camera permission). The sync task
  (task below) flips the toggle to enabled (Req 14, 12.1).

`SettingsViewModel` persists GPS accuracy:

```swift
@Observable
final class SettingsViewModel {
    private let defaults: UserDefaults
    var accuracy: TrackingAccuracy { didSet { persistAccuracy() } }   // "Balanced" | "High"
    // reads on init; the composition root passes the persisted value into RideTuning for
    // the next ride. Units are read-only ("Miles · mph") in the MVP.
}
```

MapKit isolation: all three map usages (Home has none; active, summary, history-detail) go
through a single small `RouteMapView` wrapper so a future renderer swap touches one file.

## Theme and shared components (Support/, Requirement 15)

```swift
enum Theme {
    enum Color {                      // asset-backed; light chrome, dark ride screen
        static let ink   = "#0B0F14"  // near-black text / dark ride background
        static let lime  = "#C8F135"  // primary action
        static let amber = "#F5A524"  // signal-lost / warning
        static let alert = "#D32F2F"  // destructive
        static let mist  = "#F4F5F7"  // light chrome background
    }
    enum Font {                       // SF Pro; metrics are bold + monospacedDigit (tabular)
        static func metric(_ size: CGFloat) -> Font   // large bold tabular numerals
        static let body: Font
        static let title: Font
    }
}
```

Shared components (one file each, used across screens):

- `PrimaryButton` — lime, ≥60pt tall, thumb-zone placement.
- `StateChip` — icon + text (Recording / Paused / GPS ready / Rear detection off / sync status).
- `StatTile` — a labeled number for the weekly card (tabular numerals).
- `RideRow` — the history/recent row (date, distance, duration, sync-status).

Principles the components enforce: at most three numbers while riding; controls in the thumb
zone with ≥60pt targets; icon + text for every state (never color alone). App chrome (Home,
History, Settings, Summary) is light; the active ride screen is dark.

## Permissions & Info.plist

- `NSLocationWhenInUseUsageDescription` — honest string (privacy steering).
- `NSCameraUsageDescription` — included as groundwork, but no MVP code requests the camera.
- Background location mode is **not** enabled in the MVP; foreground + screen-on is the
  reliable demo path. Enabling it later is a documented task with
  `NSLocationAlwaysAndWhenInUseUsageDescription` and the `location` background mode.

## Error & Degradation Handling

| Scenario                     | Behavior                                                             | Req  |
| ---------------------------- | ------------------------------------------------------------------- | ---- |
| Permission undetermined      | Prompt on first Start with honest string                            | 2.1  |
| Permission denied/restricted | Explanation + Open-Settings; history still usable                   | 2.2/2.3 |
| Services disabled device-wide| Same non-blocking explanation path                                  | 2.6  |
| Authorization changes live   | VM observes `onAuthorizationChange`; UI updates, no restart         | 2.4  |
| Permission revoked mid-ride  | Stop appending, surface, let user stop & save (row 11)              | 11.1 |
| Bad-accuracy / implausible fix| Discarded before append (rows 3/4)                                 | 4.2/4.3 |
| GPS signal lost mid-ride     | `signalLost` + non-alarming banner; ride retained                   | 4.4/5.3 |
| App backgrounded/terminated  | Points persisted incrementally / on lifecycle events                | 3.6  |
| Corrupt stored ride          | Skipped in list, logged, non-fatal                                  | 7.7  |
| Low power / thermal          | Keep running, possibly reduced accuracy; camera off in MVP          | 11.2 |
| Ride stopped                 | `stopUpdating`; no leaked tracking                                  | 11.3 |
| Offline / Supabase down      | Ride saved locally, marked pending, retried on foreground           | 12.4 |

## Testing Strategy

Automated unit tests (fast, no device; run before each task is marked done):

- `RideMetrics` — distance/avg across fixtures: empty, single, two-point, known multi-point
  route within tolerance; divide-by-zero guard.
- `WeeklyStatsCalculator` (Req 13) — with injected `now` + `Calendar`: no rides; rides outside
  the current week; rides on the week start/end boundaries; a week spanning a DST change; zero-
  distance rides; correct Mon–Sun bucketing and totals.
- `RideSessionViewModel` — all 14 transition-table rows via `FakeLocationTracker` + `TestClock`,
  including accuracy/jump filtering, signal-loss timeout and recovery, pause excluded from
  active duration, revoked-mid-ride, and undefined-transition no-ops. The press-and-hold Stop
  and its VoiceOver custom action both drive the same `stop` intent (Req 3.4/3.9).
- Repositories — `InMemoryRideRepository` and `SwiftDataRideRepository` (in-memory container):
  save/list ordering/get/delete, `deleteAll` wipes everything (Req 7.8), permanence across
  reload, corrupt-record skip.
- `SettingsViewModel` (Req 14) — GPS accuracy persists to and loads from `UserDefaults` and
  maps to `RideTuning.accuracy`; "Delete all rides" calls `deleteAll()`.
- Formatters (Req 10) — miles/mph/feet and duration formatting for zero, typical, and large
  values, including the 10-mile decimal switch and the 1-hour duration switch.
- Sync (Req 12) — `RoutePrivacy.trim` edge cases; `SyncCoordinator` with a fake
  `RideSyncService`: saves locally before upload, marks pending on failure, retries without
  duplicates, propagates deletes after reconnect, never runs while sync is disabled.
- Permission flow — VM responses to each `LocationAuthorizationStatus` and to failures.

Manual on-device verification (documented in the task, not automated):

- Real GPS accuracy on a short walk/ride, live map rendering/auto-follow, lifecycle
  persistence by backgrounding mid-ride, battery sanity, VoiceOver/Dynamic Type spot check,
  the press-and-hold Stop gesture (hold progress + accidental-tap rejection) and its VoiceOver
  custom action, the non-dismissible active-ride cover, and the Home dashboard rendering with
  real rides.

## Decisions (settled October 24, 2026)

| # | Decision            | Choice                                                | Why                                                     |
| - | ------------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| 1 | Minimum iOS         | iOS 17                                                | iPhone 14 is the demo device; keeps teammates' phones   |
| 2 | Persistence         | SwiftData locally + opt-in Supabase sync               | Offline-safe demo; Supabase feeds the web dashboard     |
| 3 | Maps                | MapKit                                                | Native, no key; Apple Developer account available       |
| 4 | Tests               | Swift Testing                                         | Bundled with Xcode 26; parameterized transition tables  |
| 5 | Project form        | Standard committed `.xcodeproj`                       | Single iOS owner; no extra tooling                      |
| 6 | Concurrency         | Xcode 26 defaults (MainActor isolation, Approachable) | Fewer Swift 6 warnings; heavy work opted off main actor |
| 7 | Units               | US customary (mi, mph, ft)                            | Boston team, US judges                                  |
| 8 | Role C              | Backend / Data & Integration (Supabase + website)     | Owns schema, RLS, and the dashboard                     |
| 9 | Identity            | Supabase anonymous sign-in                            | Enables RLS with no PII                                 |
| 10| Navigation          | `NavigationStack`, Home as hub; ride = full-screen cover| Matches mockups; can't swipe-abandon a ride           |
| 11| Stop control        | Press-and-hold (~1s) + VoiceOver custom action        | Prevents accidental ride-end; still accessible          |
| 12| Home dashboard      | Weekly-stats card + Mon–Sun chart via pure `WeeklyStats`| Motivating Home; aggregation stays testable            |
| 13| Settings            | First-class screen (accuracy, units, delete-all, sync) | Mockup-driven; GPS accuracy is functional now           |
| 14| Rear detection UI   | Visible non-functional placeholder, 3 places, no camera | Honest "experimental"; never requests camera in MVP    |
| 15| Design system       | `Theme` tokens + shared components; light chrome/dark ride| Consistency; three-numbers/60pt/icon+text principles  |

Still open: the Supabase schema itself, until Role C marks it "Agreed" in
`.kiro/team/supabase-contract.md`.

## Key Decisions & Rationale (summary)

- **iOS 17 + SwiftData + Observation:** maximizes velocity; acceptable device cutoff for a demo.
- **MapKit:** no API key, no cost, native polyline rendering; isolated behind one wrapper view.
- **Protocols for all framework access + a Clock:** parallel teammate work and deterministic,
  device-free tests.
- **Explicit state machine:** turns permission-denied, GPS-loss, revocation, and interruption
  from edge-case bugs into named, tested states.
- **Camera/detection deferred to seams:** honors "don't claim collision prediction" and "never
  block a ride," and avoids requesting camera permission before a feature needs it.
- **Points as an encoded blob on the record:** avoids thousands of rows per ride; swappable.
- **Local-first with opt-in Supabase sync:** the web dashboard gets data without the demo
  depending on venue Wi-Fi; privacy zones and RLS keep uploaded routes safe.
- **NavigationStack hub + non-dismissible ride cover + press-and-hold Stop:** matches the
  mockups and makes accidental ride-loss (swipe/tap) structurally impossible while keeping an
  accessible VoiceOver alternative.
- **Pure `WeeklyStats` behind the Home dashboard:** a motivating Home screen whose numbers are
  computed by a deterministic, calendar-injected function that's trivial to test (DST, week
  boundaries, empty, zero-distance).
- **Design system (`Theme` + components):** one source of truth for color, typography (tabular
  metric numerals), and the three-numbers / 60pt / icon+text principles; light chrome, dark
  ride screen.
