import Foundation

/// Configurable constants for the ride engine, gathered in one place
/// (Requirements 4.2/4.3/4.4/4.7) so values are not hard-coded at call sites.
///
/// Documented defaults:
/// - `maxAcceptableAccuracyMeters`: fixes worse than this are discarded.
/// - `signalLossTimeout`: no acceptable fix for this long → `signalLost`.
/// - `maxPlausibleSpeedMetersPerSecond`: implied-speed sanity cap (~78 mph).
/// - `accuracy`: GPS accuracy profile for the next ride (fed from Settings).
/// - `maxStoredPoints`: point cap policy; `nil` = no cap for the MVP (a
///   conscious, documented decision per Requirement 4.7).
struct RideTuning: Equatable, Sendable {
    var maxAcceptableAccuracyMeters: Double = 30
    var signalLossTimeout: TimeInterval = 8
    var maxPlausibleSpeedMetersPerSecond: Double = 35
    var accuracy: TrackingAccuracy = .high
    var maxStoredPoints: Int? = nil

    init(
        maxAcceptableAccuracyMeters: Double = 30,
        signalLossTimeout: TimeInterval = 8,
        maxPlausibleSpeedMetersPerSecond: Double = 35,
        accuracy: TrackingAccuracy = .high,
        maxStoredPoints: Int? = nil
    ) {
        self.maxAcceptableAccuracyMeters = maxAcceptableAccuracyMeters
        self.signalLossTimeout = signalLossTimeout
        self.maxPlausibleSpeedMetersPerSecond = maxPlausibleSpeedMetersPerSecond
        self.accuracy = accuracy
        self.maxStoredPoints = maxStoredPoints
    }
}
