import Foundation

/// Pure timing/scaling math for the simulated-ride player (demo-mode design
/// "Playback", Requirement 5.3/5.8). It contains no `Clock`, no timers, and no
/// framework: given a script, a playback speed factor, and the elapsed playback
/// time since the ride started, it answers "which scripted points are due to
/// have been delivered by now, and which are withheld because they fall inside
/// the signal-loss gap". The `SimulatedRouteTracker` wraps this with the
/// injected `Clock` so tests stay deterministic.
///
/// Accelerated playback scales the *delivery schedule* only: a point whose
/// script offset is `t` is scheduled for playback time `t / speedFactor`. The
/// scripted `offsetSeconds` are never mutated, so the ride's distance, duration,
/// and average speed (derived from the points' real timestamps) are identical at
/// 1× and at any accelerated speed.
enum SimulatedRidePlayerCore {
    /// The playback time (seconds since playback start) at which `point` is
    /// delivered, under `speedFactor`. Points inside the signal-loss window are
    /// still *scheduled* (so later points keep their timing) but are withheld by
    /// `duePoints` — see `isWithheld`.
    nonisolated static func deliveryTime(
        for point: ScriptedRoutePoint,
        speedFactor: Double
    ) -> TimeInterval {
        let factor = max(speedFactor, .leastNonzeroMagnitude)
        return point.offsetSeconds / factor
    }

    /// The total playback wall-time (seconds) a script takes under `speedFactor`.
    nonisolated static func playbackDuration(
        of script: DemoRideScript,
        speedFactor: Double
    ) -> TimeInterval {
        let factor = max(speedFactor, .leastNonzeroMagnitude)
        return script.totalDuration / factor
    }

    /// `true` iff the point lies strictly inside the script's signal-loss gap
    /// and must be withheld so the ride engine's loss timeout trips and the
    /// amber banner appears. The gap is half-open `[start, end)`: the
    /// `.signalLossEnd` point (the first fix after signal returns) is delivered
    /// normally.
    nonisolated static func isInSignalLossGap(
        _ point: ScriptedRoutePoint,
        in script: DemoRideScript
    ) -> Bool {
        guard let window = script.signalLossWindow else { return false }
        return window.contains(point.offsetSeconds)
    }

    /// `true` iff the point lies strictly inside the script's pause segment
    /// `[start, end)`. The player withholds pause-interior points (the rider is
    /// stopped); the controller drives the real `pause()`/`resume()` on the ride
    /// engine at the pause boundaries, so the loss timer is cancelled and the
    /// pause segment never trips signal-lost. The `.pauseStart` boundary point
    /// is still delivered (it is the last fix before the pause).
    nonisolated static func isInPauseSegment(
        _ point: ScriptedRoutePoint,
        in script: DemoRideScript
    ) -> Bool {
        guard let window = script.pauseWindow else { return false }
        // Deliver the `.pauseStart` point itself; withhold the interior points
        // up to (not including) `.pauseEnd`.
        return point.offsetSeconds > window.lowerBound && point.offsetSeconds < window.upperBound
    }

    /// `true` iff the point is withheld for any reason (signal-loss gap or the
    /// interior of a pause segment) and must not be delivered through
    /// `onLocation`.
    nonisolated static func isWithheld(
        _ point: ScriptedRoutePoint,
        in script: DemoRideScript
    ) -> Bool {
        isInSignalLossGap(point, in: script) || isInPauseSegment(point, in: script)
    }

    /// The points that should have been delivered by `elapsedPlayback` seconds of
    /// playback at `speedFactor`, in script order, excluding points withheld by
    /// the signal-loss gap.
    ///
    /// A point is "due" when its scaled delivery time is ≤ `elapsedPlayback`.
    nonisolated static func duePoints(
        in script: DemoRideScript,
        speedFactor: Double,
        elapsedPlayback: TimeInterval
    ) -> [ScriptedRoutePoint] {
        script.points.filter { point in
            !isWithheld(point, in: script)
                && deliveryTime(for: point, speedFactor: speedFactor) <= elapsedPlayback
        }
    }

    /// The not-yet-due points, in script order (withheld points are excluded —
    /// they are never delivered). Useful for scheduling the next emission.
    nonisolated static func pendingPoints(
        in script: DemoRideScript,
        speedFactor: Double,
        elapsedPlayback: TimeInterval
    ) -> [ScriptedRoutePoint] {
        script.points.filter { point in
            !isWithheld(point, in: script)
                && deliveryTime(for: point, speedFactor: speedFactor) > elapsedPlayback
        }
    }
}
