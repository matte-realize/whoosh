# Design — Whoosh Ride Recording MVP

## Overview

This design implements the ride-recording MVP with an MVVM + service-layer architecture.
The guiding constraints: UI is thin and declarative, all framework access (Core Location,
persistence) sits behind protocols, ride lifecycle is an explicit state machine, and the
future camera/alert subsystems exist only as protocol seams. Everything demo-critical runs
on-device with no network.

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
┌──────────────────────────────────────────────────────────┐
│                         SwiftUI Views                      │
│  HomeView · ActiveRideView · RideSummaryView · HistoryView │
└───────────────┬────────────────────────────────────────────┘
                │ observe state / send intents
┌───────────────▼────────────────────────────────────────────┐
│                      ViewModels (@Observable)                │
│   RideSessionViewModel · HistoryViewModel · SummaryVM        │
└───────┬───────────────────────┬───────────────┬─────────────┘
        │                       │               │
┌───────▼────────┐   ┌──────────▼───────┐  ┌─────▼──────────────┐
│ LocationTracking│   │  RideRepository  │  │  HazardDetector /  │
│   (protocol)    │   │   (protocol)     │  │  AlertManager      │
│                 │   │                  │  │  (future seams)    │
│ CoreLocation-   │   │ SwiftDataRide-   │  │ NoopDetector /     │
│ Tracker · Fake  │   │ Repository · Fake│  │ StubAlertManager   │
└─────────────────┘   └──────────────────┘  └────────────────────┘
        │                       │
   ┌────▼─────┐           ┌─────▼──────┐
   │  Clock   │           │ Domain<->  │
   │ (protocol│           │ Record map │
   │ for tests)│          └────────────┘
   └──────────┘
```

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
}
```

- `SwiftDataRideRepository` maps `Ride` ↔ `RideRecord` (the `@Model`).
- `InMemoryRideRepository` (fake) backs unit tests and SwiftUI previews.

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

## UI Layer

All views are driven by `@Observable` view models; no framework objects are constructed
inside views.

- **HomeView** — primary "Start Ride" button, entry to history, empty-state. Reads auth
  status from the view model to decide prompt vs. explanation. One-handed, large targets
  (Req 1.6).
- **ActiveRideView** — MapKit `Map` with a `MapPolyline` of collected points + user-location
  indicator, live elapsed/distance, pause/resume/stop controls, and a state banner
  (recording/paused/signal-lost) that uses icon+text not color alone (Req 10.5). Auto-follows
  current location with manual-pan tolerance (Req 5.5).
- **RideSummaryView** — full-route map + distance/duration/avg speed; reused for a just-
  finished ride and a history detail (Req 6.5).
- **HistoryView** — list most-recent-first with date/distance/duration, swipe-to-delete with
  confirmation, tap-through to summary, empty-state.

MapKit isolation: all three map usages go through a single small `RouteMapView` wrapper so a
future renderer swap touches one file.

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
- `RideSessionViewModel` — all 14 transition-table rows via `FakeLocationTracker` + `TestClock`,
  including accuracy/jump filtering, signal-loss timeout and recovery, pause excluded from
  active duration, revoked-mid-ride, and undefined-transition no-ops.
- Repositories — `InMemoryRideRepository` and `SwiftDataRideRepository` (in-memory container):
  save/list ordering/get/delete, permanence across reload, corrupt-record skip.
- Formatters (Req 10) — miles/mph/feet and duration formatting for zero, typical, and large
  values, including the 10-mile decimal switch and the 1-hour duration switch.
- Sync (Req 12) — `RoutePrivacy.trim` edge cases; `SyncCoordinator` with a fake
  `RideSyncService`: saves locally before upload, marks pending on failure, retries without
  duplicates, propagates deletes after reconnect, never runs while sync is disabled.
- Permission flow — VM responses to each `LocationAuthorizationStatus` and to failures.

Manual on-device verification (documented in the task, not automated):

- Real GPS accuracy on a short walk/ride, live map rendering/auto-follow, lifecycle
  persistence by backgrounding mid-ride, battery sanity, VoiceOver/Dynamic Type spot check.

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
