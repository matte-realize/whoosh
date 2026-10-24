import Foundation

/// The pure, unit-tested normal-mode rear-vehicle alert gate (demo-mode design
/// "The normal-mode gate", Requirement 4.1/4.2).
///
/// A rear-vehicle detection is delivered to `AlertManager` **only while** a ride
/// is actively `recording` **and** the rider's current speed exceeds the
/// configured threshold (`DemoTuning.minAlertSpeedMetersPerSecond`, default
/// 2 m/s). In every other ride state — `paused`, `signalLost`, `idle`,
/// `finished` — or at or below the threshold speed, the gate stays closed so a
/// stationary or resting rider is not alerted.
///
/// The forced-alert demo (Requirement 4.3) deliberately bypasses this gate; this
/// type defines the rule the demo bypasses and the rule a real detector will
/// plug into. It is an experimental cautionary cue, not a guarantee: it cannot
/// guarantee detection or delivery.
enum RearAlertGate {
    /// `true` iff a rear-vehicle alert should be delivered to `AlertManager` in
    /// normal mode.
    nonisolated static func shouldDeliver(
        rideState: RideState,
        currentSpeed: Double,
        tuning: DemoTuning
    ) -> Bool {
        switch rideState {
        case .recording:
            return currentSpeed > tuning.minAlertSpeedMetersPerSecond
        case .paused, .signalLost, .idle, .finished:
            return false
        }
    }
}
