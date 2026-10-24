import Foundation

/// A `LocationTracking` implementation that plays a bundled `DemoRideScript`
/// through the existing location seam, so a simulated ride drives the real
/// `RideSessionViewModel` and every downstream screen exactly as real GPS would
/// (demo-mode design option A, Requirement 5.1/5.3/5.4/5.7/5.8).
///
/// It never touches `CLLocationManager`: it synthesizes `RoutePoint`s from the
/// script and delivers them on the injected `Clock`'s schedule, scaled by the
/// playback speed factor. Points inside the script's signal-loss window are
/// withheld long enough to trip the ride engine's loss timeout, so the real
/// amber signal-lost banner appears with no special-casing in the engine.
///
/// Because a simulated ride uses this tracker and a real ride uses
/// `CoreLocationTracker`, one ride is always all-scripted or all-real — the
/// "no mixing" guarantee (Requirement 5.4) is structural.
///
/// Main-actor isolated (project default): callbacks are delivered on the main
/// actor like every other tracker, so the view model consumes them directly.
@MainActor
final class SimulatedRouteTracker: LocationTracking {
    // MARK: LocationTracking

    /// A simulated ride is always "authorized"; it needs no real permission.
    let authorizationStatus: LocationAuthorizationStatus = .authorizedWhenInUse

    var onAuthorizationChange: ((LocationAuthorizationStatus) -> Void)?
    var onLocation: ((RoutePoint) -> Void)?
    var onFailure: ((LocationFailure) -> Void)?

    // MARK: Injected dependencies

    private let script: DemoRideScript
    private let clock: Clock
    /// Base `Date` used to convert a point's `offsetSeconds` into an absolute
    /// `RoutePoint.timestamp`. The scripted timestamps (not wall-clock) drive the
    /// ride's distance/duration, so a point's timestamp stays `base + offset`
    /// regardless of playback speed, keeping the summary identical at 1× and
    /// accelerated speeds (Requirement 5.3).
    private let rideStart: Date
    private(set) var speedFactor: Double

    // MARK: State

    /// `true` between `startUpdating` and `stopUpdating`.
    private(set) var isUpdating = false
    /// Pending scheduled emissions, cancelled on `stopUpdating`.
    private var scheduled: [Cancellable] = []
    /// Number of points emitted so far (for tests).
    private(set) var emittedCount = 0

    /// - Parameters:
    ///   - script: the scripted route to play.
    ///   - clock: the injected clock seam (real `SystemClock` in the app,
    ///     `TestClock` in tests).
    ///   - speedFactor: 1× by default; accelerated factors (e.g. 4×, 10×) scale
    ///     the delivery schedule only.
    ///   - rideStart: base date for synthesized timestamps; defaults to the
    ///     clock's current instant so a live ride's timestamps look real.
    init(
        script: DemoRideScript,
        clock: Clock,
        speedFactor: Double = 1,
        rideStart: Date? = nil
    ) {
        self.script = script
        self.clock = clock
        self.speedFactor = max(speedFactor, .leastNonzeroMagnitude)
        self.rideStart = rideStart ?? clock.now()
    }

    // MARK: LocationTracking

    func requestWhenInUseAuthorization() {
        // Already authorized; mirror a real tracker by notifying once.
        onAuthorizationChange?(authorizationStatus)
    }

    func startUpdating(accuracy: TrackingAccuracy) {
        // Re-applying accuracy mid-ride (power/thermal) must not restart the
        // scripted playback; only schedule once per start.
        guard !isUpdating else { return }
        isUpdating = true
        scheduleAllPoints()
    }

    func stopUpdating() {
        isUpdating = false
        cancelScheduled()
    }

    // MARK: Playback

    /// Schedule every non-withheld scripted point for delivery via the clock,
    /// at `offsetSeconds / speedFactor` seconds from now. Points inside the
    /// signal-loss window are never scheduled (withheld), so the engine's loss
    /// timeout trips during the gap.
    private func scheduleAllPoints() {
        for point in script.points
        where !SimulatedRidePlayerCore.isWithheld(point, in: script) {
            let delay = SimulatedRidePlayerCore.deliveryTime(
                for: point,
                speedFactor: speedFactor
            )
            let token = clock.schedule(after: delay) { [weak self] in
                self?.deliver(point)
            }
            scheduled.append(token)
        }
    }

    private func deliver(_ point: ScriptedRoutePoint) {
        guard isUpdating else { return }
        emittedCount += 1
        onLocation?(makeRoutePoint(point))
    }

    /// Convert a scripted point to a `RoutePoint` using scripted timestamps, so
    /// the ride's metrics are speed-factor-independent (Requirement 5.3).
    private func makeRoutePoint(_ point: ScriptedRoutePoint) -> RoutePoint {
        RoutePoint(
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: rideStart.addingTimeInterval(point.offsetSeconds),
            speedMetersPerSecond: point.speedMetersPerSecond,
            horizontalAccuracyMeters: point.horizontalAccuracyMeters
        )
    }

    private func cancelScheduled() {
        for token in scheduled { token.cancel() }
        scheduled.removeAll()
    }
}
