import Foundation

/// The demo-path crash detector (spec Requirement 5.3 / 19.9, design D23,
/// crash-response task 23). It emits a probable-crash signal **only on demand**
/// via `simulateCrash(isDrill:)`, reachable from the "Simulate crash" control
/// that is itself gated behind the "Developer / demo tools" toggle in Settings
/// → Crash alerts. It never emits on its own — there is no sensor, timer, or
/// network behind it.
///
/// A simulated crash runs the **real** coordinator and (when wired) the real
/// notifier so judges see the real flow without crashing a bike. Signals are
/// marked `isDrill = true` by default, so the resulting message uses the `drill`
/// template ("WHOOSH DEMO - NOT REAL"), the countdown hides "Call 911", the log
/// labels it a demo, and it does not consume the real-alert per-ride cap
/// (enforced by the reducer, not here).
///
/// The trigger API is intentionally tiny (`simulateCrash(isDrill:)`) so the
/// later demo-mode integration (a separate branch) can drive the same simulator
/// from a global Demo toggle without changing this type.
///
/// On-device, non-blocking, no camera, no network, no motion — it is a plain
/// signal source behind the `CrashDetector` seam. It mirrors `NoopCrashDetector`
/// except that `simulateCrash` can emit while monitoring.
final class DebugCrashSimulator: CrashDetector {
    var onSignal: ((CrashSignal) -> Void)?

    /// The source label recorded on emitted signals.
    static let sourceLabel = "simulator"

    /// Injected clock so the signal's timestamp is deterministic in tests and
    /// consistent with the coordinator's clock in the app.
    private let clock: Clock

    /// `true` between `start()` and `stop()`. A simulated crash is delivered
    /// only while monitoring, matching the real detectors (a disarmed/stopped
    /// detector observes nothing).
    private(set) var isMonitoring = false

    init(clock: Clock) {
        self.clock = clock
    }

    // MARK: - CrashDetector

    func start() { isMonitoring = true }

    func stop() { isMonitoring = false }

    // MARK: - Demo trigger

    /// Emit a probable-crash signal through `onSignal` (the demo path). The
    /// coordinator still decides whether to act (it may be disarmed, suppressed,
    /// or capped). Delivered only while monitoring.
    ///
    /// - Parameter isDrill: `true` (default) uses the `drill` template and does
    ///   not consume the real-alert cap; `false` exercises the real `crash_alert`
    ///   path for an end-to-end rehearsal.
    func simulateCrash(isDrill: Bool = true) {
        guard isMonitoring else { return }
        let signal = CrashSignal(
            timestamp: clock.now(),
            confidence: 1.0,
            source: Self.sourceLabel,
            isDrill: isDrill
        )
        onSignal?(signal)
    }
}
