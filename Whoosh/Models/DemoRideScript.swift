import Foundation

/// A bundled, pure, Foundation-only scripted route for the simulated ride
/// (demo-mode design "Data: the scripted route", Requirement 5.2/5.8). It is a
/// value type checked into the app target as data, fully unit-testable without a
/// device.
///
/// A script is an ordered list of `ScriptedRoutePoint`s with monotonic
/// `offsetSeconds`, including at least one pause segment and one short
/// signal-loss gap so the paused state and the amber signal-lost banner both
/// appear during the demo.
struct DemoRideScript: Equatable, Sendable {
    /// Human-readable name, e.g. "Charles River Loop".
    let name: String
    /// Ordered points; `offsetSeconds` strictly increases.
    let points: [ScriptedRoutePoint]

    init(name: String, points: [ScriptedRoutePoint]) {
        self.name = name
        self.points = points
    }

    /// Total scripted duration (seconds): the last point's offset, or 0 when
    /// empty. Independent of playback speed.
    nonisolated var totalDuration: TimeInterval {
            points.last?.offsetSeconds ?? 0
        }

    /// `true` iff offsets are strictly increasing (a well-formed script).
    nonisolated var hasMonotonicOffsets: Bool {
            guard points.count > 1 else { return true }
            return zip(points, points.dropFirst()).allSatisfy { $0.offsetSeconds < $1.offsetSeconds }
        }

    /// The signal-loss window as the half-open `[start, end)` offset range, if
    /// the script declares one via `.signalLossStart` / `.signalLossEnd`
    /// markers. `end` is the offset of the first point after the gap.
    nonisolated var signalLossWindow: Range<TimeInterval>? {
            guard let start = points.first(where: { $0.marker?.isSignalLossStart == true })?.offsetSeconds,
                  let end = points.first(where: { $0.marker?.isSignalLossEnd == true })?.offsetSeconds,
                  start < end else {
                return nil
            }
            return start..<end
        }

    /// The pause window as the half-open `[start, end)` offset range, if the
    /// script declares one via `.pauseStart` / `.pauseEnd` markers.
    nonisolated var pauseWindow: Range<TimeInterval>? {
            guard let start = points.first(where: { $0.marker?.isPauseStart == true })?.offsetSeconds,
                  let end = points.first(where: { $0.marker?.isPauseEnd == true })?.offsetSeconds,
                  start < end else {
                return nil
            }
            return start..<end
        }
}

extension DemoRideScript {
    /// The single bundled Charles River / Mass Ave loop for v1 (O-DM8). Realistic
    /// coordinates in Cambridge/Boston along the Charles, with plausible cycling
    /// speeds (~5 m/s ≈ 11 mph), horizontal accuracies, one pause segment (rider
    /// stopped at a light), and one short signal-loss gap (points withheld long
    /// enough to trip the MVP's 8 s loss timeout so the amber banner appears).
    ///
    /// Regular fixes are spaced 4 s apart — comfortably under the ride engine's
    /// 8 s signal-loss timeout — so the ride stays `recording` between fixes and
    /// only the deliberate 12 s gap (offsets 120 → 132) trips the amber banner.
    /// The pause segment (offsets 60 → 84) is driven by the controller calling
    /// `pause()`/`resume()`; the player withholds the pause interior.
    static let charlesRiverLoop = DemoRideScript(
        name: "Charles River Loop",
        points: [
            // Depart near the Harvard Bridge (MIT side), heading east along the
            // Charles on Memorial Drive.
            ScriptedRoutePoint(latitude: 42.354300, longitude: -71.091600, offsetSeconds: 0, speedMetersPerSecond: 0, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.354380, longitude: -71.091060, offsetSeconds: 4, speedMetersPerSecond: 3.6, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.354500, longitude: -71.090520, offsetSeconds: 8, speedMetersPerSecond: 4.6, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.354650, longitude: -71.089980, offsetSeconds: 12, speedMetersPerSecond: 5.1, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.354820, longitude: -71.089440, offsetSeconds: 16, speedMetersPerSecond: 5.3, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.355000, longitude: -71.088900, offsetSeconds: 20, speedMetersPerSecond: 5.4, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.355190, longitude: -71.088360, offsetSeconds: 24, speedMetersPerSecond: 5.4, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.355380, longitude: -71.087820, offsetSeconds: 28, speedMetersPerSecond: 5.3, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.355560, longitude: -71.087300, offsetSeconds: 32, speedMetersPerSecond: 5.2, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.355720, longitude: -71.086800, offsetSeconds: 36, speedMetersPerSecond: 5.0, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.355860, longitude: -71.086340, offsetSeconds: 40, speedMetersPerSecond: 4.6, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.355980, longitude: -71.085940, offsetSeconds: 44, speedMetersPerSecond: 4.0, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.356080, longitude: -71.085600, offsetSeconds: 48, speedMetersPerSecond: 3.2, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.356150, longitude: -71.085360, offsetSeconds: 52, speedMetersPerSecond: 2.2, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.356190, longitude: -71.085220, offsetSeconds: 56, speedMetersPerSecond: 1.0, horizontalAccuracyMeters: 8),
            // Pause segment: stopped at a signalled crossing (offsets 60 → 84).
            ScriptedRoutePoint(latitude: 42.356210, longitude: -71.085160, offsetSeconds: 60, speedMetersPerSecond: 0, horizontalAccuracyMeters: 9, marker: .pauseStart),
            // ...pause interior withheld by the player...
            // Resume riding.
            ScriptedRoutePoint(latitude: 42.356280, longitude: -71.084720, offsetSeconds: 84, speedMetersPerSecond: 3.4, horizontalAccuracyMeters: 8, marker: .pauseEnd),
            ScriptedRoutePoint(latitude: 42.356420, longitude: -71.084200, offsetSeconds: 88, speedMetersPerSecond: 4.8, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.356580, longitude: -71.083680, offsetSeconds: 92, speedMetersPerSecond: 5.2, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.356750, longitude: -71.083160, offsetSeconds: 96, speedMetersPerSecond: 5.4, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.356920, longitude: -71.082640, offsetSeconds: 100, speedMetersPerSecond: 5.4, horizontalAccuracyMeters: 6),
            ScriptedRoutePoint(latitude: 42.357090, longitude: -71.082120, offsetSeconds: 104, speedMetersPerSecond: 5.3, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.357260, longitude: -71.081600, offsetSeconds: 108, speedMetersPerSecond: 5.3, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.357430, longitude: -71.081080, offsetSeconds: 112, speedMetersPerSecond: 5.2, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.357600, longitude: -71.080560, offsetSeconds: 116, speedMetersPerSecond: 5.2, horizontalAccuracyMeters: 7),
            // Signal-loss gap: last fix before a 12 s hole (> 8 s loss timeout).
            ScriptedRoutePoint(latitude: 42.357770, longitude: -71.080040, offsetSeconds: 120, speedMetersPerSecond: 5.1, horizontalAccuracyMeters: 8, marker: .signalLossStart),
            // ...12 s hole, offsets (120, 132) — no points emitted...
            // First fix after signal returns.
            ScriptedRoutePoint(latitude: 42.358280, longitude: -71.078480, offsetSeconds: 132, speedMetersPerSecond: 4.9, horizontalAccuracyMeters: 10, marker: .signalLossEnd),
            ScriptedRoutePoint(latitude: 42.358450, longitude: -71.077960, offsetSeconds: 136, speedMetersPerSecond: 5.0, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.358620, longitude: -71.077440, offsetSeconds: 140, speedMetersPerSecond: 5.0, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.358790, longitude: -71.076920, offsetSeconds: 144, speedMetersPerSecond: 4.8, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.358940, longitude: -71.076460, offsetSeconds: 148, speedMetersPerSecond: 4.2, horizontalAccuracyMeters: 7),
            ScriptedRoutePoint(latitude: 42.359060, longitude: -71.076080, offsetSeconds: 152, speedMetersPerSecond: 3.4, horizontalAccuracyMeters: 8),
            // Ease to a stop at the finish.
            ScriptedRoutePoint(latitude: 42.359150, longitude: -71.075800, offsetSeconds: 156, speedMetersPerSecond: 2.2, horizontalAccuracyMeters: 8),
            ScriptedRoutePoint(latitude: 42.359200, longitude: -71.075640, offsetSeconds: 160, speedMetersPerSecond: 0.8, horizontalAccuracyMeters: 9),
        ]
    )
}
