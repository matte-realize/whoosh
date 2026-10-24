import Foundation

/// The default `CrashDetector`: monitoring is inert and **no signal is ever
/// emitted** (spec Requirement 5.8). Injected at the composition root when crash
/// detection is off, so the coordinator always has a non-optional detector.
///
/// Contains no network, camera, or motion code; `start()` / `stop()` are no-ops.
final class NoopCrashDetector: CrashDetector {
    var onSignal: ((CrashSignal) -> Void)?

    init() {}

    /// No-op: the Noop detector never begins monitoring.
    func start() {}

    /// No-op: nothing to stop.
    func stop() {}
}
