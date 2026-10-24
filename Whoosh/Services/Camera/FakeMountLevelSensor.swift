import Foundation

/// Scriptable `MountLevelSensing` for tests and SwiftUI previews: gravity samples
/// are delivered on command so the level view model and the pure `LevelCalculator`
/// (task 9) can be exercised without Core Motion.
///
/// Lives under `Services/Camera/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Scripting:
/// - `start()` / `stop()` toggle `isSensing` and record counts; samples are only
///   delivered while sensing is active.
/// - `emit(_:)` delivers one gravity sample; `emitGravity(_:)` delivers several
///   in order.
/// Callbacks fire synchronously on the main actor so expectations are
/// deterministic.
@MainActor
final class FakeMountLevelSensor: MountLevelSensing {
    var onGravity: ((GravityVector) -> Void)?

    private(set) var isSensing = false

    // MARK: Recorded interactions (for test assertions)

    /// Number of `start` calls.
    private(set) var startCount = 0
    /// Number of `stop` calls.
    private(set) var stopCount = 0

    init() {}

    // MARK: MountLevelSensing

    func start() {
        isSensing = true
        startCount += 1
    }

    func stop() {
        isSensing = false
        stopCount += 1
    }

    // MARK: Scripting API (test/preview driven)

    /// Deliver a single gravity sample through `onGravity` (only while sensing).
    func emit(_ gravity: GravityVector) {
        guard isSensing else { return }
        onGravity?(gravity)
    }

    /// Deliver several gravity samples in order (only while sensing).
    func emitGravity(_ samples: [GravityVector]) {
        for sample in samples { emit(sample) }
    }
}
