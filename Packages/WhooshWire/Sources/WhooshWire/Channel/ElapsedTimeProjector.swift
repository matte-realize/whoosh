import Foundation

/// Projects the ride's elapsed active time on the watch from a skew-free anchor
/// (watch-companion design "`ElapsedTimeProjector` and `CrashCountdownModel`
/// (pure)"; Requirement 8.2). Pure value type.
///
/// The phone sends `activeMs` (the active duration **at send**) inside
/// `WireRideStatus`. The watch records the value of its **own monotonic clock**
/// at the moment the status arrives, then advances the displayed elapsed time by
/// the monotonic delta while the ride is `recording` or `signalLost`, and
/// freezes it while `paused`. It never subtracts a phone wall-clock from a watch
/// wall-clock (design time rule L3), so clock skew and transport latency never
/// corrupt the number.
public struct ElapsedTimeProjector: Equatable, Sendable {
    /// The active duration (ms) carried by the last applied status.
    public private(set) var anchorActiveMs: Int
    /// The watch monotonic clock reading (ms) when that status was applied.
    public private(set) var anchorMonotonicMs: Int
    /// The ride state carried by the last applied status (gates ticking).
    public private(set) var state: WireRideState

    public init(
        anchorActiveMs: Int = 0,
        anchorMonotonicMs: Int = 0,
        state: WireRideState = .idle
    ) {
        self.anchorActiveMs = anchorActiveMs
        self.anchorMonotonicMs = anchorMonotonicMs
        self.state = state
    }

    /// Re-anchor from a freshly received status.
    ///
    /// - Parameters:
    ///   - activeMs: the status `activeMs` (active duration at send).
    ///   - monotonicNowMs: the watch's monotonic clock reading right now.
    ///   - state: the status ride state.
    public mutating func apply(activeMs: Int, monotonicNowMs: Int, state: WireRideState) {
        self.anchorActiveMs = max(0, activeMs)
        self.anchorMonotonicMs = monotonicNowMs
        self.state = state
    }

    /// The elapsed active ms to display at the given monotonic clock reading.
    ///
    /// While `recording` / `signalLost` the display advances with the monotonic
    /// delta since the anchor; while `paused` (or any non-running state) it is
    /// frozen at the anchor value. A monotonic reading before the anchor (should
    /// not happen) never produces a negative projection.
    public func elapsedMs(monotonicNowMs: Int) -> Int {
        switch state {
        case .recording, .signalLost:
            let delta = max(0, monotonicNowMs - anchorMonotonicMs)
            return anchorActiveMs + delta
        default:
            return anchorActiveMs
        }
    }
}
