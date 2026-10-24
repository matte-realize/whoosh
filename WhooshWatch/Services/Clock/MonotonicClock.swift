import Foundation

/// A monotonic clock seam for the watch app (watch-companion design "time rule
/// L3": every elapsed/remaining/staleness computation uses the watch's own
/// monotonic clock, never a phone/watch wall-clock subtraction). The pure
/// package types (`WatchRideReducer`, `WatchCommandTracker`, `CrashCountdownModel`,
/// `WristHapticLimiter`) take an `Int` millisecond reading; this protocol is how
/// the model obtains it, and lets tests and previews inject a controllable clock.
public protocol MonotonicClock: Sendable {
    /// A monotonically increasing reading in milliseconds. Never decreases; the
    /// absolute origin is arbitrary (only differences are meaningful).
    var nowMs: Int { get }
}

/// The real monotonic clock, based on `DispatchTime.uptimeNanoseconds`
/// (unaffected by wall-clock changes; design "no wall-clock subtraction").
public struct UptimeMonotonicClock: MonotonicClock {
    public init() {}

    public var nowMs: Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

/// A controllable clock for previews and tests: `nowMs` returns whatever the
/// caller last set (or advanced). Reference type so a view/preview can advance
/// it over time.
public final class FakeMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _nowMs: Int

    public init(startMs: Int = 0) {
        self._nowMs = startMs
    }

    public var nowMs: Int {
        lock.lock(); defer { lock.unlock() }
        return _nowMs
    }

    /// Set the clock to an absolute reading.
    public func set(_ ms: Int) {
        lock.lock(); defer { lock.unlock() }
        _nowMs = ms
    }

    /// Advance the clock by `ms` milliseconds.
    public func advance(by ms: Int) {
        lock.lock(); defer { lock.unlock() }
        _nowMs += ms
    }
}
