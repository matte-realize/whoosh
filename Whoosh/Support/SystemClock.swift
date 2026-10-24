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
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            work()
        }
        return TimerCancellable(timer: timer)
    }

    /// Wraps a `Timer` so cancelling invalidates it.
    private struct TimerCancellable: Cancellable {
        let timer: Timer
        func cancel() { timer.invalidate() }
    }
}
