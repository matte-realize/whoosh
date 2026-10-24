import Foundation

/// Configurable constants for Demo mode, gathered in one place so values are not
/// hard-coded at call sites (demo-mode design "DemoTuning (constants)"). Pure,
/// Foundation-only value type so it lives in the Models layer.
///
/// Documented defaults:
/// - `minAlertSpeedMetersPerSecond`: the normal-mode rear-alert gate only opens
///   above this speed (~4.5 mph), so a stationary or resting rider is not
///   buzzed (Requirement 4.1).
/// - `defaultSpeedFactor`: simulated-ride playback speed when none is chosen (1×).
/// - `acceleratedSpeedFactors`: the accelerated playback options (e.g. 4×, 10×)
///   offered by the demo tools so a multi-minute route plays in under a minute
///   (Requirement 5.3).
/// - `autoAlertInterval`: default period for the forced-alert auto-trigger
///   (Requirement 4.4).
struct DemoTuning: Equatable, Sendable {
    /// Minimum speed (m/s) above which the normal-mode rear-vehicle alert gate
    /// opens. Default 2 m/s (~4.5 mph).
    var minAlertSpeedMetersPerSecond: Double

    /// Playback speed factor used when no accelerated speed is selected.
    var defaultSpeedFactor: Double

    /// Accelerated playback factors offered by the demo tools.
    var acceleratedSpeedFactors: [Double]

    /// Default interval (seconds) between auto-triggered forced rear alerts.
    var autoAlertInterval: TimeInterval

    init(
        minAlertSpeedMetersPerSecond: Double = 2,
        defaultSpeedFactor: Double = 1,
        acceleratedSpeedFactors: [Double] = [4, 10],
        autoAlertInterval: TimeInterval = 10
    ) {
        self.minAlertSpeedMetersPerSecond = minAlertSpeedMetersPerSecond
        self.defaultSpeedFactor = defaultSpeedFactor
        self.acceleratedSpeedFactors = acceleratedSpeedFactors
        self.autoAlertInterval = autoAlertInterval
    }
}
