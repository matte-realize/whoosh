import Foundation

/// A handle to cancel scheduled work. Kept as a tiny protocol (rather than
/// `Combine.AnyCancellable`) so the `Clock` seam stays Foundation-only and the
/// `TestClock` can provide a trivial deterministic token.
protocol Cancellable {
    func cancel()
}

/// Abstracts time so signal-loss timeouts and durations are testable without
/// waiting in real time (design "Clock" seam / Requirement 4.6).
///
/// `now()` returns the current instant; `schedule(after:_:)` runs `work` after
/// the interval and returns a `Cancellable`. `SystemClock` wraps `Date()` and a
/// timer; `TestClock` (test support) advances time manually and fires scheduled
/// work deterministically.
protocol Clock {
    func now() -> Date
    @discardableResult
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
}
