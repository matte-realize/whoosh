import Foundation

/// A device gravity vector (unit-ish acceleration due to gravity in the device
/// frame), the input the pure `LevelCalculator` (task 9) turns into roll/pitch
/// for the Mount & frame level indicator (rear-camera spec Requirement 9.1,
/// design "Mount & frame: Level"). Foundation-only so the Models/Metrics layers
/// and tests never import Core Motion.
///
/// `Equatable`, `Codable`, `Sendable` so it compares in tests and crosses actors.
struct GravityVector: Equatable, Codable, Sendable {
    /// Gravity along the device x-axis.
    let x: Double
    /// Gravity along the device y-axis.
    let y: Double
    /// Gravity along the device z-axis.
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Abstracts the Core Motion gravity stream so Mount & frame and tests never
/// touch Core Motion (rear-camera spec Requirement 9, design "Service protocols:
/// MountLevelSensing"). `MountLevelSensor` (task 22) is the only concrete type
/// that reads `CMMotionManager`; `FakeMountLevelSensor` scripts gravity samples
/// for tests and previews.
///
/// ## Contract (see privacy steering and the design)
/// - **Mount & frame only.** Motion is read solely to help the rider level the
///   phone before the ride; it is not recorded, uploaded, logged, or transmitted.
/// - **Main actor delivery.** `onGravity` is delivered on the main actor so the
///   level view model updates directly. Start/stop are lifecycle-scoped to the
///   Mount & frame screen — leaving it tears the sensor down.
/// - **Never stops GPS.** The level sensor is independent of ride GPS recording.
///
/// `AnyObject` because a concrete sensor is a long-lived reference type owning
/// the motion manager.
@MainActor
protocol MountLevelSensing: AnyObject {
    /// Invoked with each gravity sample while sensing is active.
    var onGravity: ((GravityVector) -> Void)? { get set }

    /// Whether sensing is currently active (between `start` and `stop`).
    var isSensing: Bool { get }

    /// Begin delivering gravity samples. Must not block.
    func start()

    /// Stop delivering samples and release the motion manager.
    func stop()
}
