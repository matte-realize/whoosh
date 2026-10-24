import Foundation

/// A **read-only** view of the active `RideSessionViewModel` for the camera
/// subsystem (rear-camera spec task 19; design "RideCameraBridge: read-only view
/// of RideSessionViewModel"). It is the same pattern the crash-response
/// `RideSessionBridge` uses: the camera coordinator reads ride state, id, start,
/// distance, and the latest route coordinate through this bridge and **never**
/// mutates the ride engine, so the finished MVP ride flow is untouched
/// (Requirement 1.3, D-CAM14).
///
/// `@MainActor` because `RideSessionViewModel` is main-actor isolated; the
/// bridge only reads its public, already-observable state.
@MainActor
final class RideCameraBridge {
    private let session: RideSessionViewModel
    private let clock: Clock

    init(session: RideSessionViewModel, clock: Clock) {
        self.session = session
        self.clock = clock
    }

    /// The ride lifecycle state.
    var rideState: RideState { session.rideState }

    /// Whether a ride is currently active (recording / paused / signal-lost).
    var isRideActive: Bool { session.rideState.isActive }

    /// The active ride's id, or `nil` when idle (used to key segments/clips).
    var rideId: UUID? { session.currentRideID }

    /// The instant the ride started, or `nil` when idle. Falls back to the
    /// first accepted route point's timestamp (the engine does not expose
    /// `startedAt` directly; the first point is a close, monotonic proxy used
    /// only for clip-window clamping).
    var rideStart: Date? {
        guard session.rideState != .idle else { return nil }
        return session.points.first?.timestamp
    }

    /// Distance of the accepted route so far, in meters.
    var distanceMeters: Double { session.distanceMeters }

    /// Instantaneous speed from the latest accepted point, in m/s, or `nil`.
    var speedMetersPerSecond: Double? {
        guard let speed = session.points.last?.speedMetersPerSecond, speed >= 0 else {
            return nil
        }
        return speed
    }

    /// The accumulated active duration at `instant` (excludes paused spans).
    func activeDuration(at instant: Date) -> TimeInterval {
        session.activeDuration(at: instant)
    }

    /// The nearest accepted route coordinate to `instant` (used to place a
    /// near-miss event). Returns the closest point by timestamp, or `nil` when
    /// there are no points. The coordinate never leaves the device.
    func routeCoordinate(at instant: Date) -> (latitude: Double, longitude: Double)? {
        let points = session.points
        guard !points.isEmpty else { return nil }
        let nearest = points.min(by: {
            abs($0.timestamp.timeIntervalSince(instant)) < abs($1.timestamp.timeIntervalSince(instant))
        })
        guard let nearest else { return nil }
        return (nearest.latitude, nearest.longitude)
    }
}
