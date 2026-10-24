import Foundation

/// Pure battery policy for the camera subsystem (rear-camera spec Requirement
/// 12.3, design "BatteryPolicy"). Maps battery level, charging state, and Low
/// Power Mode to a recommendation: keep the requested profile, suggest the
/// Efficient profile, or stop the camera so GPS can finish the ride.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The caller
/// supplies the battery fraction and flags (from a power monitor behind a
/// protocol); this type never reads the device.
///
/// ## Rules (design table)
/// - ≤ 20% unplugged ⇒ suggest the Efficient profile (and apply it automatically
///   when Low Power Mode is on).
/// - ≤ 8% unplugged ⇒ **stop** the camera (GPS continues).
/// - Charging cancels both suggestions and the stop.
/// - Low Power Mode ⇒ default to the Efficient profile.
enum BatteryPolicy {
    /// What the battery policy recommends.
    enum Recommendation: Equatable, Sendable {
        /// Keep the requested profile.
        case keep
        /// Use the Efficient profile (low battery or Low Power Mode).
        case useEfficient
        /// Stop the camera so GPS can complete the ride.
        case stop
    }

    /// The inputs. `batteryLevel` is a 0...1 fraction.
    struct Input: Equatable, Sendable {
        /// Battery charge as a 0...1 fraction.
        let batteryLevel: Double
        /// Whether the device is charging (plugged in).
        let isCharging: Bool
        /// Whether Low Power Mode is enabled.
        let isLowPowerMode: Bool
        /// The tuning floors.
        let tuning: RideCameraTuning

        init(
            batteryLevel: Double,
            isCharging: Bool,
            isLowPowerMode: Bool,
            tuning: RideCameraTuning = RideCameraTuning()
        ) {
            self.batteryLevel = batteryLevel
            self.isCharging = isCharging
            self.isLowPowerMode = isLowPowerMode
            self.tuning = tuning
        }
    }

    /// Decide the recommendation for the given inputs.
    static func decide(_ input: Input) -> Recommendation {
        // Charging overrides the stop and suggest floors, but Low Power Mode
        // still defaults the profile to Efficient (it can be on while charging).
        if input.isCharging {
            return input.isLowPowerMode ? .useEfficient : .keep
        }

        // Unplugged: stop at or below the stop floor.
        if input.batteryLevel <= input.tuning.batteryStopFloor {
            return .stop
        }

        // Unplugged: suggest Efficient at or below the suggest floor, or whenever
        // Low Power Mode is on.
        if input.batteryLevel <= input.tuning.batterySuggestEfficient || input.isLowPowerMode {
            return .useEfficient
        }

        return .keep
    }
}
