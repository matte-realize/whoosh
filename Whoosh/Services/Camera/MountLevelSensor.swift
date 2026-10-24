import CoreMotion
import Foundation

/// The only Core Motion owner for the Mount & frame level indicator (rear-camera
/// spec Requirement 9.1, task 22; design "Mount & frame: Level"). It streams the
/// device gravity vector to the level view model, which converts it to roll/pitch
/// with the pure `LevelCalculator`. Core Motion is allowed in `Services/Camera/`
/// by the privacy script.
///
/// ## Contract (see privacy steering and `MountLevelSensing`)
/// - **Mount & frame only.** Motion is read solely to help the rider level the
///   phone before the ride; it is never recorded, uploaded, logged, or
///   transmitted, and the sensor is torn down when the screen is left.
/// - **Main actor delivery.** Device-motion updates are requested onto the main
///   queue so `onGravity` is delivered on the main actor.
/// - **Never stops GPS.** The level sensor is independent of ride GPS recording;
///   if device motion is unavailable it simply delivers nothing.
///
/// Device-verified (task 31); the simulator has no motion hardware.
@MainActor
final class MountLevelSensor: MountLevelSensing {
    var onGravity: ((GravityVector) -> Void)?

    private(set) var isSensing = false

    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval

    /// - Parameter updateInterval: how often to sample gravity (default ~20 Hz,
    ///   plenty for a bubble-level readout).
    init(updateInterval: TimeInterval = 1.0 / 20.0) {
        self.updateInterval = updateInterval
    }

    func start() {
        guard !isSensing else { return }
        guard motionManager.isDeviceMotionAvailable else { return }
        isSensing = true
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = motion.gravity
            self.onGravity?(GravityVector(x: g.x, y: g.y, z: g.z))
        }
    }

    func stop() {
        guard isSensing else { return }
        isSensing = false
        motionManager.stopDeviceMotionUpdates()
    }
}
