import Foundation

/// The production `Clock`: real wall-clock time and a `Timer`-based scheduler.
///
/// Scheduling uses a non-repeating `Timer` added to the main run loop, matching
/// the app's main-actor default isolation (the ride engine that consumes the
/// clock runs on the main actor). Tests use `TestClock` instead, so this type
/// never has to be driven deterministically.
final class SystemClock: Clock {
    init() {}

    func now() -> Date { Date() }

    @discardableResult
    func schedule(
        after interval: TimeInterval,
        _ work: @escaping () -> Void
    ) -> Cancellable {
        // The clock is consumed on the main actor (default isolation). Wrap the
        // non-Sendable `work` so the `@Sendable` timer closure can call it back
        // on the main actor without a data-race warning.
        let box = WorkBox(work)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated { box.work() }
        }
        return TimerCancellable(timer: timer)
    }

    /// A main-actor-isolated holder for the scheduled work, letting the
    /// `@Sendable` timer closure defer execution to the main actor. Marked
    /// `@unchecked Sendable` because it is only ever touched on the main actor.
    private final class WorkBox: @unchecked Sendable {
        let work: () -> Void
        init(_ work: @escaping () -> Void) { self.work = work }
    }

    /// Wraps a `Timer` so cancelling invalidates it.
    private struct TimerCancellable: Cancellable {
        let timer: Timer
        func cancel() { timer.invalidate() }
    }
}
