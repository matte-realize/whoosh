# Requirements — Whoosh Ride Recording MVP

## Introduction

This spec defines the first shippable slice of Whoosh: a polished SwiftUI app that records a
cycling ride with GPS, shows the route on a map, and persists ride history on-device. It
establishes a modular architecture (service protocols, state machines) so camera-based
hazard detection and haptic alerts can be added later without rework. The UI follows the
reviewed mockups in `design/mockups/whoosh-mvp-mockups-v0.1.svg` (7 screens): a Home hub with
a weekly-stats dashboard, the active ride screen, the ride summary, history, settings, and the
location-denied state.

Out of scope for this spec: camera capture, hazard detection models, haptic/audio collision
warnings, background location, email/password accounts, and routing. These appear only as
protocol seams, documented under "Future" where relevant. Rear vehicle detection appears in
the MVP only as a **visible, non-functional, experimental placeholder** (Home card, a ride-
screen "off" chip, and a disabled Settings row); it never requests camera permission.

In scope as a non-blocking stretch: opt-in sync of finished rides to Supabase (Requirement
12), so Role C's web dashboard can display them. The Supabase schema is owned by Role C; the
app implements against it only once it's agreed.

New in this revision (post-mockup review): a Home dashboard with a weekly-stats card and
weekday chart backed by a pure `WeeklyStats` function (Requirement 13); a first-class Settings
screen (Requirement 14); and a documented design system / theme (Requirement 15). Navigation
is a `NavigationStack` with Home as the hub; the active ride is a non-dismissible full-screen
cover; Stop is press-and-hold, not a tap.

The app targets iOS 17+, SwiftUI, MapKit, Core Location, and SwiftData. These are the
**recommended** defaults; the design document records alternatives, and the team may revise
them as implementation proceeds (see the design's "Revisability" note). Requirements below
describe the *behavior and outcomes* the MVP must deliver — not a specific implementation —
so they remain valid even if a particular framework choice changes.

## How to read this document

- Acceptance criteria use EARS-style phrasing (WHEN/WHILE/IF ... THEN ... SHALL ...) so each
  is individually verifiable.
- Each requirement lists a **priority**: `Demo-critical` (must work live), `Important`
  (strongly expected), or `Future-seam` (defined now, built later).
- "Configurable" means the value lives in one place (a settings/constants type) and is not
  hard-coded at call sites; it does not mandate a user-facing setting.
- Units: distances in meters, durations in seconds, speeds in meters/second internally;
  display uses US customary units (miles, mph, feet), covered in Requirement 10.

## Glossary

- **Ride** — a single recording session from start to stop, with an ordered set of route
  points and a computed summary.
- **Route point** — one GPS sample: coordinate, timestamp, instantaneous speed, and accuracy.
- **Signal loss** — a period during an active ride where no acceptable location updates
  arrive for longer than a configured interval.
- **Acceptable fix** — a location sample whose horizontal accuracy is within the configured
  threshold.

---

## Requirement 1: App foundation and navigation

**Priority:** Demo-critical

**User story:** As a cyclist, I want a clear, simple app so I can find ride recording and my
past rides without confusion.

### Acceptance Criteria

1. WHEN the app launches THEN the system SHALL display a Home screen that acts as the hub,
   with a prominent, single primary "Start Ride" action and clearly labeled ways to reach
   ride history and settings.
2. WHEN the user has never recorded a ride AND opens history THEN the system SHALL display a
   friendly empty-state message (not a blank list and not an error).
3. The app SHALL build and launch on an iOS 17 simulator with no compiler warnings in
   first-party app code (third-party/framework warnings excepted).
4. The app SHALL use a `NavigationStack` with Home as the root hub; History and Settings SHALL
   be pushed from Home and SHALL offer a back control labeled "Home". The finished-ride summary
   SHALL be presented after Stop and SHALL be dismissed with an explicit "Done" control.
5. WHILE a ride is active THE system SHALL present the active-ride screen as a full-screen
   cover that CANNOT be swipe-dismissed, so the in-progress ride is never lost through normal
   navigation. Ending a ride SHALL require the explicit press-and-hold Stop gesture defined in
   Requirement 3; incidental taps and back-swipes SHALL NOT end a ride.
6. The primary ride controls SHALL be reachable and operable one-handed in the thumb zone and
   SHALL use touch targets at least 60pt (supporting the "don't stare at the screen" goal).

## Requirement 2: Location permission handling

**Priority:** Demo-critical

**User story:** As a cyclist, I want the app to ask for location access clearly and keep
working even if I decline, so I'm never stuck.

### Acceptance Criteria

1. WHEN the user starts their first ride AND location permission is `notDetermined` THEN the
   system SHALL request "When In Use" authorization accompanied by an honest usage
   description string (see privacy steering).
2. IF the user denies or restricts location permission THEN the Home screen SHALL render a
   location-denied state that contains: a plain explanation of why location is needed; a
   numbered "Open Settings" help sequence (1. Open Settings, 2. tap Location, 3. choose
   "While Using the App"); an "Open Settings" button that deep-links to the system Settings
   for the app; and a "View past rides" button. The app SHALL NOT crash, hang, or dead-end.
3. IF location permission is denied THEN the system SHALL still allow the user to open and
   browse ride history (the "View past rides" path SHALL remain reachable from the Home
   denied state).
4. WHEN authorization status changes while the app is running (including returning from
   Settings) THEN the system SHALL reflect the new status in the UI without requiring a
   restart.
5. WHEN permission is `authorizedWhenInUse` THEN the system SHALL NOT additionally prompt for
   "Always" authorization in the MVP (background tracking is a future seam).
6. IF location services are disabled device-wide THEN the system SHALL present the same
   non-blocking explanation path as a per-app denial.

## Requirement 3: Ride recording lifecycle

**Priority:** Demo-critical

**User story:** As a cyclist, I want to start, pause, resume, and stop a ride so I control
exactly what gets recorded.

### Acceptance Criteria

1. WHEN the user taps "Start Ride" AND location is authorized THEN the system SHALL create a
   new ride, enter the `recording` state, record a start timestamp, and begin requesting
   location updates.
2. WHEN a ride is `recording` AND the user taps "Pause" THEN the system SHALL enter `paused`,
   stop appending location points, and retain all data collected so far. Pause and Resume
   SHALL be single taps.
3. WHEN a ride is `paused` AND the user taps "Resume" THEN the system SHALL re-enter
   `recording` and resume appending points, without duplicating or back-filling points for
   the paused interval.
4. WHEN the user performs an explicit press-and-hold on "Stop" (~1 second) from any active
   state (`recording`, `paused`, `signalLost`) THEN the system SHALL finalize the ride, record
   an end timestamp, compute its summary, persist it, and transition to `finished`. The Stop
   control SHALL show visible hold progress while the gesture is in flight; releasing before
   the threshold SHALL cancel with no state change. An incidental tap or a back-swipe SHALL
   NOT end a ride.
5. The ride lifecycle SHALL be modeled as an explicit, documented state machine with states
   `idle`, `recording`, `paused`, `signalLost`, and `finished`, and only the transitions
   listed in the design SHALL be permitted; attempts at undefined transitions SHALL be
   no-ops rather than crashes.
6. IF the app is backgrounded or terminated while a ride is active THEN the system SHALL NOT
   silently lose already-collected points; the collected data SHALL be recoverable or already
   persisted. (MVP approach: persist incrementally and/or on lifecycle events. Full
   uninterrupted background recording is a future enhancement.)
7. WHEN a ride is finalized with zero acceptable points THEN the system SHALL still complete
   the stop transition and produce a valid (zeroed) summary rather than erroring.
8. The elapsed-time measure for a ride SHALL exclude paused intervals (ride time reflects
   moving/active time, not wall-clock since start). The exact definition is specified in the
   design and SHALL be unit-tested.
9. The press-and-hold Stop gesture SHALL have an accessible alternative: a VoiceOver custom
   action labeled "Stop ride" that finalizes the ride without requiring the timed hold, so the
   feature is operable without the gesture.

## Requirement 4: GPS track collection

**Priority:** Demo-critical

**User story:** As a cyclist, I want my route recorded accurately so my summary and map are
trustworthy.

### Acceptance Criteria

1. WHILE a ride is `recording` THE system SHALL append each acceptable location point
   (coordinate, timestamp, speed, horizontal accuracy) to the current ride in arrival order.
2. The system SHALL discard points whose horizontal accuracy is worse than a configurable
   threshold (default documented in the design) so the route is not polluted by bad fixes.
3. The system SHOULD discard or de-weight points that imply an implausible speed/jump
   relative to the previous accepted point (a configurable sanity filter), so a single wild
   fix cannot corrupt distance. This is `Important`, not demo-blocking.
4. IF no acceptable location update arrives for longer than a configurable interval WHILE
   `recording` THEN the system SHALL enter `signalLost` and surface it in the UI.
5. WHEN an acceptable location update arrives WHILE in `signalLost` THEN the system SHALL
   return to `recording` and resume appending points.
6. The point-collection, acceptance-filtering, and signal-loss-timer logic SHALL be
   unit-testable without a real GPS device, driven through the location service protocol with
   injected fixtures and a controllable clock.
7. The system SHALL cap or thin stored points if a ride becomes extremely long, OR document
   that no cap is applied for the MVP, so memory behavior is a conscious decision rather than
   unbounded by accident.

## Requirement 5: Live ride map and metrics

**Priority:** Demo-critical

**User story:** As a cyclist, I want to glance at my current route and stats so I know the
app is working.

### Acceptance Criteria

1. WHILE a ride is active THE system SHALL display the active-ride screen using the dark theme,
   with a map showing the route collected so far as a continuous line and an indicator of the
   current location.
2. WHILE a ride is active THE system SHALL display at most three numbers: ride time (large,
   primary), distance, and current speed, updating as new points arrive. Ride time uses the
   active-duration definition (Requirement 3.8).
3. WHEN the ride is in `signalLost` THE system SHALL display an amber banner reading "GPS
   signal lost — Your ride continues. Resuming..." that is clearly non-alarming and conveys
   that recording resumes automatically.
4. WHILE a ride is `paused` THE system SHALL reuse the same layout as `recording` and visually
   distinguish paused via the state chip (icon + text), not color alone.
5. The active-ride screen SHALL show a state chip with both icon and text ("Recording" or
   "Paused"), and SHALL show a non-functional "Rear detection off" chip (experimental
   placeholder; see Requirement 15/8). State SHALL always be conveyed by icon + text, never
   color alone.
6. The map SHOULD keep the current location and recent route in view as the ride progresses
   (reasonable auto-follow), while not fighting the user if they manually pan. Auto-follow
   refinement is `Important`, not demo-blocking.
7. Live metric display SHALL remain smooth and SHALL NOT block the UI thread while points are
   processed.

## Requirement 6: Ride summary

**Priority:** Demo-critical

**User story:** As a cyclist, I want a summary when I finish so I can see how the ride went.

### Acceptance Criteria

1. WHEN a ride finishes THEN the system SHALL display total distance, total active duration,
   average speed, and a map of the full route.
2. The summary metrics SHALL be computed by pure, framework-free functions that are
   unit-tested against known fixtures, including empty, single-point, two-point, and a
   multi-point route with a known expected distance (within a documented tolerance).
3. IF a ride has zero or one recorded points THEN the system SHALL display a sensible summary
   (zero distance, zero or near-zero duration) rather than an error or NaN.
4. Average speed SHALL be defined as total distance divided by total active duration, with a
   defined result (e.g., zero) when duration is zero, and this definition SHALL be
   unit-tested.
5. The summary view SHALL be reusable for both a just-finished ride and a past ride opened
   from history (same component, different data source).
6. The summary view SHALL display a sync-status row using icon + text ("On device",
   "Pending", or "Synced"); until cloud sync exists (Requirement 12) every ride SHALL show
   "On device". Once sync exists AND a ride has been synced, the summary SHALL also show a
   "Start and end trimmed for privacy" note.

## Requirement 7: Ride history and persistence

**Priority:** Demo-critical

**User story:** As a cyclist, I want my past rides saved so I can review and manage them.

### Acceptance Criteria

1. WHEN a ride is finished THEN the system SHALL persist it to local storage durably enough
   to survive app relaunch.
2. WHEN the user opens history THEN the system SHALL list past rides most-recent-first,
   grouped by month under a month header that shows the month's ride count and total miles.
   Each row SHALL show at least date/time, distance, duration, and a sync-status indicator
   using icon + text ("On device" / "Pending" / "Synced"); until cloud sync exists
   (Requirement 12) every ride SHALL show "On device".
3. WHEN the user selects a past ride THEN the system SHALL display its full summary and route
   using the same summary component as a just-finished ride.
4. WHEN the user deletes a ride (swipe-to-delete with a Delete button) AND confirms THEN the
   system SHALL remove it permanently from local storage, and it SHALL NOT reappear after
   relaunch.
5. All persistence access SHALL go through a repository abstraction so the storage engine is
   swappable and can be replaced by a fake in tests. The specific engine (SwiftData is the
   recommended default) is an implementation choice recorded in the design and MAY change.
6. No ride data SHALL leave the device unless the user has explicitly enabled cloud sync
   (Requirement 12). Local storage SHALL remain the source of truth either way.
7. IF a stored ride cannot be decoded or is corrupt THEN the system SHALL skip it gracefully
   in the list rather than crashing, and SHOULD surface a non-fatal indication.
8. The repository SHALL expose a `deleteAll()` operation that permanently removes every stored
   ride (real deletion, not a soft flag). It SHALL be available on both the in-memory fake and
   the SwiftData implementation and SHALL be unit-tested. It is invoked from the Settings
   "Delete all rides" destructive action behind a confirmation alert (Requirement 14); if a
   deleted ride was synced, remote deletion is requested later once sync exists (Requirement
   12.6).

## Requirement 8: Extensibility seams (defined now, built later)

**Priority:** Future-seam

**User story:** As a developer on the team, I want clear seams so I can add camera detection
and alerts later without rewriting the app.

### Acceptance Criteria

1. The system SHALL define a `HazardDetector` abstraction describing detection input and
   output at a level that does not lock in a specific vision/ML approach, with a no-op
   implementation used by the MVP.
2. The system SHALL define an `AlertManager` abstraction for haptic/audio alerts, with a stub
   implementation used by the MVP.
3. These abstractions SHALL be documented with the contract that implementations run
   on-device for immediate safety alerts and must never block, slow, or stop ride recording.
4. No camera permission SHALL be requested by the MVP; camera permission SHALL be requested
   only when a feature that needs it is actually enabled by the user in a future version.
5. The seams SHALL be defined such that a teammate can implement them in parallel against the
   abstraction without needing to modify the ride-recording code.
6. The abstractions SHOULD be expressive enough to later carry data needed for near-miss
   logging (e.g., a timestamped detection event tied to a route point) without a redesign,
   but the MVP SHALL NOT implement near-miss logging.
7. The MVP SHALL surface rear vehicle detection as a **visible, non-functional, experimental
   placeholder** in three places: a "Rear vehicle detection — Experimental, coming soon" card
   on Home, a "Rear detection off" chip on the active-ride screen, and a disabled "Soon" row
   in Settings. These placeholders SHALL NOT request camera permission and SHALL NOT imply the
   feature works; copy SHALL be framed as experimental. (`Future-seam`.)

## Requirement 9: Privacy and permissions compliance

**Priority:** Demo-critical

**User story:** As a cyclist, I want to trust that my data stays mine.

### Acceptance Criteria

1. The app SHALL include honest, purpose-specific usage description strings for every
   permission it can request, matching the privacy steering.
2. WHILE cloud sync is disabled THE app SHALL make no network requests. The app SHALL
   include no analytics or tracking SDKs; the pinned Supabase client is the only networking
   dependency. Both SHALL be verifiable by inspecting dependencies and code.
3. UI copy and marketing-style text in the app SHALL NOT claim the app predicts, prevents, or
   guarantees avoidance of collisions; detection-related copy SHALL be framed as experimental.
4. WHEN the user deletes a ride, or deletes all rides from Settings, THEN deletion SHALL be
   real and local (not a soft flag that leaves data recoverable off-device), consistent with
   "user owns their data."

## Requirement 10: Units, formatting, and accessibility

**Priority:** Important

**User story:** As a cyclist, I want readable numbers and an app I can use regardless of my
abilities.

### Acceptance Criteria

1. The system SHALL display distance in miles (two decimals under 10 mi, one decimal
   above), speed in mph (one decimal), and short distances in feet where shown, and SHALL
   format durations human-readably (`m:ss` under an hour, `h:mm:ss` above).
2. Formatting logic SHALL be centralized and unit-tested for representative values including
   zero and large values.
3. Interactive controls SHALL carry accessibility labels, and dynamic content (metrics,
   state banners) SHALL be exposed to VoiceOver. The press-and-hold Stop gesture SHALL have a
   VoiceOver custom action alternative (Requirement 3.9) so it is operable without the hold.
4. The UI SHOULD support Dynamic Type without truncating primary ride controls or metrics.
5. Color SHALL NOT be the only signal for any state (ride state, sync status, detection
   placeholder); an icon or text label SHALL always accompany it.
6. Primary controls SHALL use touch targets of at least 60pt and SHALL sit within the one-
   handed thumb zone, per the design system (Requirement 15).

## Requirement 11: Resilience and failure handling

**Priority:** Important

**User story:** As a cyclist, I want the app to behave sanely when things go wrong.

### Acceptance Criteria

1. IF location permission is revoked mid-ride THEN the system SHALL stop appending points,
   surface the situation, and preserve the ride data collected so far (treated like a
   terminal signal loss the user can stop and save).
2. IF the device enters a low-power or thermally-throttled condition THEN the app SHALL
   continue functioning (possibly at reduced location accuracy) and SHALL NOT crash. Battery
   is a documented concern; the MVP keeps the camera off to limit draw.
3. The app SHALL NOT retain strong references that keep location updates running after a ride
   is stopped (no leaked tracking, for battery and privacy).
4. Any error surfaced to the user SHALL be actionable or dismissible and SHALL NOT expose raw
   framework error text as the only message.

## Requirement 12: Opt-in cloud sync (Supabase)

**Priority:** Important (stretch; never demo-blocking)

**User story:** As a cyclist, I want to optionally upload my finished rides so they appear on
the Whoosh website, without making the app depend on the internet.

### Acceptance Criteria

1. Cloud sync SHALL be disabled by default and enabled only through an explicit user toggle
   in the Settings screen (Requirement 14) that states what is uploaded and that camera video
   is never uploaded. Until the sync tasks ship, this toggle SHALL appear with a disabled
   "Coming soon" label; completing the sync tasks enables it.
2. All sync access SHALL go through a `RideSyncService` abstraction; the MVP SHALL ship a
   no-op implementation, and the Supabase implementation SHALL be swappable and fakeable in
   tests.
3. WHEN sync is enabled AND a ride finishes THEN the system SHALL save the ride locally first
   and only then attempt upload; upload failure SHALL NOT affect the local ride.
4. IF the upload fails or the device is offline THEN the system SHALL mark the ride as
   pending and retry on a later trigger (app foreground or next ride finish), without
   duplicate remote rows (upload is idempotent on ride `id`).
5. Before upload, the system SHALL trim the route's first and last configurable distance
   (default 160 m / ~0.1 mi) as a privacy zone; the local route SHALL remain complete.
6. WHEN the user deletes a synced ride THEN the system SHALL delete it locally immediately
   and request remote deletion, retrying if offline.
7. The app SHALL ship only the Supabase anon key, loaded from a gitignored config file, and
   SHALL rely on Row Level Security so a user can access only their own rows.
8. Identity SHALL use Supabase anonymous sign-in for the hackathon build; no PII SHALL be
   collected.
9. The app SHALL implement sync only against a schema marked "Agreed" in
   `.kiro/team/supabase-contract.md`.
10. Each ride row in history SHOULD show its sync status (local only, pending, synced) using
    icon and text, not color alone.

---

## Requirement 13: Home dashboard and weekly stats

**Priority:** Important

**User story:** As a cyclist, I want a Home screen that welcomes me and shows how much I've
ridden this week so the app feels alive and motivating.

### Acceptance Criteria

1. The Home screen SHALL display, in the order shown in the mockup: the Whoosh wordmark, a
   "Ready to ride?" greeting, a This-Week stats card, a Recent rides list, a rear-detection
   placeholder card, a prominent "Start Ride" button, and a "GPS ready" status chip.
2. The This-Week stats card SHALL show total miles, ride count, total active time, and a
   Monday–Sunday 7-bar chart of distance per weekday for the current week.
3. The Recent rides list SHALL show the latest 2–3 rides with a "See all" control that
   navigates to History.
4. The weekly aggregation SHALL be computed by a pure, framework-free `WeeklyStats` function
   whose inputs are the rides, the current `now`, and a `Calendar`, and whose output provides
   `totalDistanceMeters`, `rideCount`, `totalActiveDuration`, and distance per weekday
   (Monday–Sunday). It SHALL NOT import SwiftUI, Core Location, SwiftData, or MapKit.
5. `WeeklyStats` SHALL be unit-tested (test-first) against edge cases: no rides; rides outside
   the current week; rides exactly on the week's start/end boundaries; a week spanning a DST
   change; and zero-distance rides.
6. WHEN there are no rides this week THEN the stats card SHALL render zeros and an empty chart
   sensibly (no error, no NaN), and the Recent rides list SHALL show a friendly empty state.
7. The rear-detection card SHALL read "Rear vehicle detection — Experimental, coming soon",
   SHALL be non-functional, and SHALL NOT request camera permission (`Future-seam`).
8. The "GPS ready" status chip SHALL reflect current location readiness using icon + text; in
   the location-denied state the Home screen SHALL render the denied state from Requirement 2
   instead of the normal dashboard.

## Requirement 14: Settings screen

**Priority:** Important

**User story:** As a cyclist, I want a Settings screen to control accuracy, see my units, and
manage my data.

### Acceptance Criteria

1. Settings SHALL be reachable from Home (pushed on the `NavigationStack`, back label "Home").
2. Settings SHALL provide a functional "GPS accuracy" control with two options, "Balanced" and
   "High", persisted in `UserDefaults` and fed into `RideTuning.accuracy`; the selected value
   SHALL survive app relaunch and SHALL be applied to the next ride.
3. Settings SHALL show a read-only "Units" row displaying "Miles · mph" for now (not yet
   user-changeable).
4. Settings SHALL provide a destructive "Delete all rides" row that, on confirmation via an
   alert, calls the repository's `deleteAll()` (Requirement 7.8). If a deleted ride was synced,
   remote deletion is requested later once sync exists.
5. Settings SHALL show the following sync-related rows DISABLED with a "Coming soon" label
   until the sync tasks ship: a "Sync rides to Whoosh map" toggle (with a plain-language
   explanation of exactly what is uploaded and that camera video is never uploaded), a
   "Privacy zone · 0.1 mi" row, and an "Identity · Anonymous" row. WHEN the sync tasks are
   complete THEN the toggle SHALL become enabled (`Future-seam` until then).
6. Settings SHALL show a disabled "Rear vehicle detection · Soon" row framed as experimental
   that does not request camera permission (`Future-seam`).
7. All Settings rows SHALL convey state with icon + text, not color alone, and use the design
   system components (Requirement 15).

## Requirement 15: Design system and theme

**Priority:** Important

**User story:** As the team, I want a shared theme and component set so every screen looks
consistent and matches the mockups.

### Acceptance Criteria

1. The app SHALL define a `Theme` in `Support/` with the color tokens Ink `#0B0F14`, Lime
   `#C8F135`, Amber `#F5A524`, Alert `#D32F2F`, and Mist `#F4F5F7`, used consistently across
   screens.
2. Typography SHALL use SF Pro, with large bold tabular (monospaced-digit) numerals for ride
   metrics so values don't jitter as they update.
3. The design system SHALL provide shared components: a primary lime button, a state chip
   (icon + text), a stat tile, and a ride row, reused across Home, the active ride, summary,
   history, and settings.
4. The design system SHALL encode the principles: at most three numbers while riding; primary
   controls within the thumb zone with touch targets of at least 60pt; and icon + text for
   every state (never color alone).
5. App chrome (Home, History, Settings, Summary) SHALL use the light theme; the active-ride
   screen SHALL use the dark theme.

---

## Non-functional notes

- **Battery:** High-accuracy continuous GPS is power-hungry; accuracy and distance filter are
  configurable so they can be tuned. The camera is off in the MVP to limit draw.
- **Reliability target:** The documented, reliable demo path is foreground recording with the
  screen on. Background recording is a future enhancement with its own permissions and risks.
- **Testability:** View models, services, repositories, metric computations, and formatters
  are unit-tested with fakes/fixtures and a controllable clock. Real Core Location, MapKit
  rendering, and device battery behavior are verified manually and documented.
- **Offline demo:** The full record → summary → history → delete flow SHALL work in
  airplane mode.
- **Revisability:** Framework and library choices (SwiftData, MapKit, Supabase, Observation,
  Swift Testing) are the chosen defaults. Because all framework access sits behind abstractions,
  these can be swapped later with localized change. Requirements are written against behavior,
  not any single implementation, so they survive such swaps.

## Traceability

Every acceptance criterion is mapped to one or more tasks in `tasks.md` via `_Requirements:_`
annotations, and the design in `design.md` references these requirement numbers where it
explains how each is satisfied.
