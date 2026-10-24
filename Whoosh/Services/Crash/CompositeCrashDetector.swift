import Foundation

/// Fans several `CrashDetector`s into one, so the coordinator (which holds a
/// single detector) can be driven by both the experimental `MotionCrashDetector`
/// (the live detector while a ride is armed) and the `DebugCrashSimulator` (the
/// demo "Simulate crash" path) at the same time (crash-response task 33).
///
/// - `start()` / `stop()` forward to every child, so the bridge arms and disarms
///   them together (the simulator's start/stop just flip a flag).
/// - Each child's `onSignal` is forwarded to this detector's single `onSignal`,
///   so a signal from either child reaches the coordinator unchanged. The
///   coordinator still decides whether to act (armed / suppressed / capped).
///
/// On-device, non-blocking, no network, no camera — it only relays signals.
@MainActor
final class CompositeCrashDetector: CrashDetector {
    var onSignal: ((CrashSignal) -> Void)? {
        didSet { rewireChildren() }
    }

    private let children: [CrashDetector]

    init(_ children: [CrashDetector]) {
        self.children = children
        rewireChildren()
    }

    func start() { children.forEach { $0.start() } }

    func stop() { children.forEach { $0.stop() } }

    /// Point every child's callback at our own `onSignal` so any child's signal
    /// is relayed. Re-run whenever our `onSignal` is (re)assigned.
    private func rewireChildren() {
        for child in children {
            child.onSignal = { [weak self] signal in
                self?.onSignal?(signal)
            }
        }
    }
}
