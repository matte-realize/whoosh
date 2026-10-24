import Foundation
import Observation

/// User-facing banner / error for the active-ride screen.
///
/// Carries only app-controlled copy — never raw framework error text
/// (Requirement 11.4). The view maps each case to localized, honest strings.
enum RideBanner: Equatable, Sendable {
    /// Acceptable updates stalled; the ride continues and resumes automatically.
    case signalLost
    /// Location permission was revoked mid-ride; the user can still stop & save.
    case permissionRevoked
    /// A ride was requested but permission is denied/restricted; show the
    /// explanation / Open-Settings path.
    case permissionNeeded
    /// A generic, actionable failure. The message is app copy, not framework text.
    case failed(message: String)
}

/// The core ride-recording state machine (Requirement 3.5), implemented as an
/// `@Observable`, main-actor view model (project default isolation; no SwiftUI
/// import, per the layering table).
///
/// Owns a `RideState` and reacts to user intents (`start`/`pause`/`resume`/
/// `stop`), location callbacks, authorization changes, failures, and a
/// signal-loss timer scheduled through the injected `Clock`. Every transition in
/// the design's 14-row table is implemented here and covered by tests driven
/// with `FakeLocationTracker` + `TestClock` + `InMemoryRideRepository`.
///
/// Active duration (Requirement 3.8) is accumulated across recording/signalLost
/// spans and excludes paused spans; `activeDuration(at:)` is a pure function a
/// `TimelineView` can tick for the live timer.
///
/// Dependencies are injected so tests are deterministic: time and `UUID`/`Date`
/// sources come from the `Clock`.
@Observable
@MainActor
final class RideSessionViewModel {
    // MARK: Injected dependencies

    @ObservationIgnored private let tracker: LocationTracking
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let repository: RideRepository
    @ObservationIgnored private let tuning: RideTuning
    /// Produces the id for a new ride; injectable for deterministic tests.
    @ObservationIgnored private let makeID: () -> UUID

    // MARK: Observable state

    /// The current lifecycle state (idle/recording/paused/signalLost/finished).
    private(set) var rideState: RideState = .idle

    /// Accepted route points for the live map.
    private(set) var points: [RoutePoint] = []

    /// The finished ride after `stop`, for the summary screen; `nil` until then.
    private(set) var finishedRide: Ride?

    /// Current authorization status, mirrored for the UI (Requirement 2.4).
    private(set) var authorizationStatus: LocationAuthorizationStatus

    /// The banner/error to surface, or `nil` when there is nothing to show.
    private(set) var banner: RideBanner?

    // MARK: Private ride bookkeeping

    @ObservationIgnored private var rideID: UUID?
    @ObservationIgnored private var startedAt: Date?
    /// Active duration accumulated from completed recording spans (seconds),
    /// excluding the currently-running span.
    @ObservationIgnored private var accumulatedActiveDuration: TimeInterval = 0
    /// Start of the current recording span, or `nil` when not recording.
    @ObservationIgnored private var lastResume: Date?
    /// Most recent accepted point, for the plausible-jump filter.
    @ObservationIgnored private var lastAcceptedPoint: RoutePoint?
    /// Pending signal-loss timer.
    @ObservationIgnored private var lossTimer: Cancellable?
    /// Set when permission is revoked mid-ride: suppresses auto-recovery so the
    /// ride stays stopped-and-saveable (row 11).
    @ObservationIgnored private var authorizationRevoked = false

    // MARK: Snapshot (task 21) bookkeeping

    /// Accepted points since the last incremental snapshot.
    @ObservationIgnored private var pointsSinceSnapshot = 0
    /// Pending periodic snapshot timer.
    @ObservationIgnored private var snapshotTimer: Cancellable?

    // MARK: Snapshot policy (task 21)

    /// Persist an in-progress snapshot after this many accepted points.
    static let snapshotEveryPoints = 10
    /// Persist an in-progress snapshot at least this often (seconds).
    static let snapshotEverySeconds: TimeInterval = 15

    init(
        tracker: LocationTracking,
        clock: Clock,
        repository: RideRepository,
        tuning: RideTuning = RideTuning(),
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.tracker = tracker
        self.clock = clock
        self.repository = repository
        self.tuning = tuning
        self.makeID = makeID
        self.authorizationStatus = tracker.authorizationStatus
        wireTrackerCallbacks()
    }

    // MARK: - Intents

    /// Start a ride. From `idle` only; authorized → `recording` (row 1),
    /// `notDetermined` → request When-In-Use and wait for the grant (row 2, no
    /// ride created), denied/restricted → `permissionNeeded` banner (row 2).
    func start() {
        guard rideState == .idle else { return }   // undefined elsewhere (rows 13/14)
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            beginRecording()
        case .notDetermined:
            // Request and start once authorized (handled in onAuthorizationChange).
            awaitingAuthorizationToStart = true
            tracker.requestWhenInUseAuthorization()
        case .denied, .restricted:
            banner = .permissionNeeded
        }
    }

    /// Pause recording (rows 5/10). No-op outside recording/signalLost.
    func pause() {
        guard rideState == .recording || rideState == .signalLost else { return }
        accumulateActiveSpan()
        cancelLossTimer()
        rideState = .paused
    }

    /// Resume recording (row 6). No-op outside paused.
    func resume() {
        guard rideState == .paused else { return }
        lastResume = clock.now()
        rideState = .recording
        armLossTimer()
    }

    /// Finalize and persist the ride (row 12). One intent for both the
    /// press-and-hold gesture and the VoiceOver custom action. No-op unless
    /// active (rows 13/14).
    func stop() {
        guard rideState.isActive else { return }
        accumulateActiveSpan()
        cancelLossTimer()
        cancelSnapshotTimer()
        tracker.stopUpdating()

        let finalized = makeFinalizedRide(endedAt: clock.now())
        persist(finalized)   // best-effort; local-first
        finishedRide = finalized
        rideState = .finished
        clearRideBookkeeping()
    }

    // MARK: - Live metrics

    /// Pure active-duration at a given instant (Requirement 3.8): accumulated
    /// completed spans plus the currently-running span while recording/signalLost.
    /// A `TimelineView` ticks this to drive the live timer.
    func activeDuration(at instant: Date) -> TimeInterval {
        guard rideState == .recording || rideState == .signalLost,
              let lastResume else {
            return accumulatedActiveDuration
        }
        return accumulatedActiveDuration + instant.timeIntervalSince(lastResume)
    }

    /// Distance of the accepted route so far, in meters (live metric).
    var distanceMeters: Double { RideMetrics.distanceMeters(points) }

    // MARK: - Task 21: mid-ride persistence safeguard

    /// Persist the current in-progress ride (`endedAt == nil`) so an interrupted
    /// ride is recoverable. Safe to call from the View layer on `scenePhase`
    /// background and ignored when no ride is active.
    func persistSnapshot() {
        guard rideState.isActive, let snapshot = makeInProgressRide() else { return }
        persist(snapshot)
        pointsSinceSnapshot = 0
    }

    /// Find a previously-saved unfinished ride (`endedAt == nil`) to offer the
    /// user for recovery on launch. Returns `nil` if there is none.
    func recoverInterruptedRide() -> Ride? {
        (try? repository.allRides())?.first { $0.endedAt == nil }
    }

    /// Finalize a recovered unfinished ride: compute its summary from the points
    /// saved before interruption and persist it as finished. Returns the
    /// finalized ride, or `nil` if it could not be recovered.
    @discardableResult
    func finalizeRecoveredRide(_ ride: Ride) -> Ride? {
        // Use the last point's timestamp as the end, falling back to startedAt,
        // so a recovered ride gets a sensible active duration without a live clock.
        let end = ride.points.last?.timestamp ?? ride.startedAt
        let duration = max(0, end.timeIntervalSince(ride.startedAt))
        var finalized = ride
        finalized.endedAt = end
        finalized.summary = RideMetrics.summary(
            points: ride.points,
            activeDuration: duration
        )
        persist(finalized)
        return (try? repository.ride(id: finalized.id)) ?? finalized
    }

    /// Finished rides only (`endedAt != nil`), most-recent-first. History shows
    /// completed rides; unfinished snapshots are excluded here rather than by
    /// changing the `RideRepository` protocol.
    func finishedRides() -> [Ride] {
        ((try? repository.allRides()) ?? []).filter { $0.endedAt != nil }
    }

    // MARK: - Tracker wiring

    @ObservationIgnored private var awaitingAuthorizationToStart = false

    private func wireTrackerCallbacks() {
        tracker.onLocation = { [weak self] point in
            self?.handleLocation(point)
        }
        tracker.onAuthorizationChange = { [weak self] status in
            self?.handleAuthorizationChange(status)
        }
        tracker.onFailure = { [weak self] failure in
            self?.handleFailure(failure)
        }
    }

    private func handleLocation(_ point: RoutePoint) {
        switch rideState {
        case .recording, .signalLost:
            break
        default:
            return   // paused ignores (row 7); idle/finished ignore
        }

        // Re-arm the loss timer on EVERY callback while active (rows 3/4):
        // accepted or not, a callback means the subsystem is alive.
        armLossTimer()

        guard isAcceptable(point) else {
            return   // row 4: discard, timer already re-armed
        }

        // Accepted fix.
        if rideState == .signalLost {
            // Row 9: recover to recording and clear the banner.
            rideState = .recording
            if banner == .signalLost { banner = nil }
        }
        points.append(point)
        lastAcceptedPoint = point

        // Task 21: incremental snapshot every N accepted points.
        pointsSinceSnapshot += 1
        if pointsSinceSnapshot >= Self.snapshotEveryPoints {
            persistSnapshot()
        }
    }

    private func handleAuthorizationChange(_ status: LocationAuthorizationStatus) {
        authorizationStatus = status

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if awaitingAuthorizationToStart && rideState == .idle {
                awaitingAuthorizationToStart = false
                beginRecording()
            }
        case .denied, .restricted:
            if awaitingAuthorizationToStart {
                // Row 2: the start request was refused; no ride was created.
                awaitingAuthorizationToStart = false
                banner = .permissionNeeded
            } else if rideState.isActive {
                // Row 11: revoked mid-ride → signalLost-style; keep the ride,
                // stop appending, let the user stop & save. No auto-recovery.
                authorizationRevoked = true
                enterSignalLost(banner: .permissionRevoked)
            }
        case .notDetermined:
            break
        }
    }

    private func handleFailure(_ failure: LocationFailure) {
        switch failure {
        case .denied:
            if awaitingAuthorizationToStart {
                awaitingAuthorizationToStart = false
                banner = .permissionNeeded
            } else if rideState.isActive {
                authorizationRevoked = true
                enterSignalLost(banner: .permissionRevoked)
            }
        case .servicesDisabled:
            if awaitingAuthorizationToStart {
                awaitingAuthorizationToStart = false
            }
            banner = .permissionNeeded
        case .unknown:
            // Never surface raw framework text (Req 11.4).
            banner = .failed(message: "Location is temporarily unavailable.")
        }
    }

    // MARK: - State helpers

    private func beginRecording() {
        let now = clock.now()
        rideID = makeID()
        startedAt = now
        lastResume = now
        accumulatedActiveDuration = 0
        points = []
        lastAcceptedPoint = nil
        finishedRide = nil
        banner = nil
        authorizationRevoked = false
        pointsSinceSnapshot = 0
        rideState = .recording
        tracker.startUpdating(accuracy: tuning.accuracy)
        armLossTimer()
        armSnapshotTimer()
    }

    /// Enter `signalLost` from an active state, surfacing a banner. Keeps updates
    /// requested (row 8) unless authorization was revoked (row 11).
    private func enterSignalLost(banner: RideBanner) {
        guard rideState == .recording || rideState == .signalLost else { return }
        // Close out the active span's elapsed time, then keep accumulating only
        // once recording resumes (lastResume stays so the live timer keeps
        // ticking the current span until recovery; for revoked we freeze it).
        if authorizationRevoked {
            accumulateActiveSpan()
        }
        rideState = .signalLost
        self.banner = banner
        cancelLossTimer()
    }

    /// The loss-timer fired: no acceptable fix within the interval (row 8).
    private func lossTimerFired() {
        guard rideState == .recording else { return }
        rideState = .signalLost
        if banner == nil { banner = .signalLost }
        // Keep updates requested; do not re-arm until a callback arrives.
    }

    private func isAcceptable(_ point: RoutePoint) -> Bool {
        // Accuracy filter (row 4 / Req 4.2): reject negative or too-coarse fixes.
        guard point.horizontalAccuracyMeters >= 0,
              point.horizontalAccuracyMeters <= tuning.maxAcceptableAccuracyMeters else {
            return false
        }
        // Plausible-jump filter (Req 4.3): reject implied speeds above the cap.
        if let previous = lastAcceptedPoint {
            let dt = point.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0 {
                let meters = RideMetrics.distanceMeters([previous, point])
                let impliedSpeed = meters / dt
                if impliedSpeed > tuning.maxPlausibleSpeedMetersPerSecond {
                    return false
                }
            }
        }
        return true
    }

    /// Fold the currently-running recording span into the accumulated total and
    /// clear `lastResume`, so pauses/stops exclude paused spans (Req 3.8).
    private func accumulateActiveSpan() {
        guard let lastResume else { return }
        accumulatedActiveDuration += clock.now().timeIntervalSince(lastResume)
        self.lastResume = nil
    }

    private func makeFinalizedRide(endedAt: Date) -> Ride {
        let id = rideID ?? makeID()
        let start = startedAt ?? endedAt
        let summary = RideMetrics.summary(
            points: points,
            activeDuration: accumulatedActiveDuration
        )
        return Ride(
            id: id,
            startedAt: start,
            endedAt: endedAt,
            points: points,
            summary: summary
        )
    }

    /// An in-progress ride (`endedAt == nil`) for incremental snapshots.
    private func makeInProgressRide() -> Ride? {
        guard let rideID, let startedAt else { return nil }
        let duration = activeDuration(at: clock.now())
        let summary = RideMetrics.summary(points: points, activeDuration: duration)
        return Ride(
            id: rideID,
            startedAt: startedAt,
            endedAt: nil,
            points: points,
            summary: summary
        )
    }

    private func persist(_ ride: Ride) {
        // Local-first and best-effort: a persistence hiccup must not break the
        // live ride or surface raw error text.
        do {
            try repository.save(ride)
        } catch {
            banner = .failed(message: "Couldn't save your ride just now.")
        }
    }

    private func clearRideBookkeeping() {
        rideID = nil
        startedAt = nil
        lastResume = nil
        lastAcceptedPoint = nil
        accumulatedActiveDuration = 0
        authorizationRevoked = false
        awaitingAuthorizationToStart = false
        pointsSinceSnapshot = 0
    }

    // MARK: - Timers

    private func armLossTimer() {
        lossTimer?.cancel()
        lossTimer = clock.schedule(after: tuning.signalLossTimeout) { [weak self] in
            self?.lossTimerFired()
        }
    }

    private func cancelLossTimer() {
        lossTimer?.cancel()
        lossTimer = nil
    }

    private func armSnapshotTimer() {
        snapshotTimer?.cancel()
        snapshotTimer = clock.schedule(after: Self.snapshotEverySeconds) { [weak self] in
            guard let self else { return }
            self.persistSnapshot()
            // Re-arm so periodic snapshots continue while active.
            if self.rideState.isActive {
                self.armSnapshotTimer()
            }
        }
    }

    private func cancelSnapshotTimer() {
        snapshotTimer?.cancel()
        snapshotTimer = nil
    }
}
