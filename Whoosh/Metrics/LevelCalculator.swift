import Foundation

/// Pure mount-level calculator for the Mount & frame screen (rear-camera spec
/// Requirement 9.1, design "Mount & frame: Level"). Converts a gravity vector
/// (unit-ish, pointing toward the ground, as Core Motion reports in
/// `CMDeviceMotion.gravity`) and the chosen mount orientation into **roll** and
/// **pitch** in degrees, then classifies them against the design's targets.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The caller in
/// `Services/Camera/` reads Core Motion and passes the three gravity components;
/// this type never imports CoreMotion.
///
/// ## Convention
/// Gravity components are in the device's coordinate space: `+x` right, `+y` up
/// (toward the top edge / earpiece), `+z` out of the screen. For a phone mounted
/// in **portrait** facing rearward:
/// - **roll** is rotation about the view axis (phone tilted left/right); target
///   `|roll| ≤ 3°`.
/// - **pitch** is the camera tilt up/down; positive = camera pointing down;
///   target `−5°…+15°`.
enum LevelCalculator {
    /// How the phone is clipped onto the mount (which way is "up").
    enum MountOrientation: String, Equatable, Sendable, CaseIterable {
        /// Portrait, top edge up (the default auto-detected posture).
        case portrait
        /// Landscape, left edge up.
        case landscapeLeft
        /// Landscape, right edge up.
        case landscapeRight
    }

    /// How level the mount is, for the icon + text indicator.
    enum Classification: String, Equatable, Sendable {
        /// Within the target ranges — good to ride.
        case level
        /// Slightly off — a warning, never a blocker.
        case slightlyOff
    }

    /// The computed roll/pitch and classification.
    struct Reading: Equatable, Sendable {
        /// Left/right tilt in degrees (0 = upright).
        let rollDegrees: Double
        /// Camera up/down tilt in degrees (positive = pointing down).
        let pitchDegrees: Double
        /// The level classification against the targets.
        let classification: Classification
    }

    /// Target absolute roll (design: `|roll| ≤ 3°`).
    static let rollTolerance: Double = 3
    /// Target pitch range (design: −5°…+15°, positive = camera down).
    static let pitchRange: ClosedRange<Double> = -5...15

    /// Compute roll and pitch (degrees) from a gravity vector and classify them.
    ///
    /// - Parameters:
    ///   - gx: gravity x (device space).
    ///   - gy: gravity y (device space).
    ///   - gz: gravity z (device space).
    ///   - orientation: the mount orientation.
    static func reading(
        gx: Double,
        gy: Double,
        gz: Double,
        orientation: MountOrientation = .portrait
    ) -> Reading {
        // Map device-space gravity into the mounted frame so "roll" and "pitch"
        // are relative to the chosen orientation.
        let (rx, ry) = rollAxes(gx: gx, gy: gy, orientation: orientation)

        // Roll: angle of the in-plane gravity projection away from straight down.
        // atan2(rx, -ry) is 0 when gravity points toward the frame's "down".
        let roll = degrees(atan2(rx, -ry))

        // Pitch: how far the view axis (z) tips out of vertical. Positive when
        // the camera points downward (gz negative means screen faces up).
        let horizontal = (rx * rx + ry * ry).squareRoot()
        let pitch = degrees(atan2(gz, horizontal))

        let classification: Classification =
            (abs(roll) <= rollTolerance && pitchRange.contains(pitch)) ? .level : .slightlyOff

        return Reading(rollDegrees: roll, pitchDegrees: pitch, classification: classification)
    }

    // MARK: - Helpers

    /// The in-plane gravity axes for the orientation. For portrait the frame's
    /// (right, up) are device (x, y); landscape rotates them.
    private static func rollAxes(
        gx: Double,
        gy: Double,
        orientation: MountOrientation
    ) -> (right: Double, up: Double) {
        switch orientation {
        case .portrait:
            return (gx, gy)
        case .landscapeLeft:
            // Device rotated 90° counter-clockwise: frame-right = device-up.
            return (gy, -gx)
        case .landscapeRight:
            // Device rotated 90° clockwise: frame-right = device-down.
            return (-gy, gx)
        }
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / Double.pi
    }
}
