import Foundation

/// The phone's view of whether the watch can carry alerts, derived by
/// `WatchChannelEvaluator` from the link state **plus** the watch's reported
/// `WireWatchState` (watch-companion design "`WatchChannelEvaluator`" table;
/// Requirement 13). The routing policy consumes this to decide which sinks run.
public enum WatchChannelState: Equatable, Sendable {
    /// Setting off, not paired/installed, or incompatible → phone channels only.
    case unavailable
    /// Installed but not reachable → phone channels only; try `startWatchApp`
    /// during a ride (with backoff).
    case unreachable
    /// Reachable, but the watch app is only active while on screen (no running
    /// workout session) → **degraded**: watch + audio.
    case foregroundOnly
    /// Fully ready: reachable ∧ session running/paused ∧ Health authorized ∧
    /// haptics armed ∧ not low battery → watch first, audio on timeout.
    case ready
    /// Ready minus one capability (low watch battery, another workout, session
    /// failed, Health denied) → watch + audio. The `reason` is a short code.
    case degraded(reason: Reason)

    public enum Reason: String, Equatable, Sendable, CaseIterable {
        case watchBatteryLow
        case anotherWorkout
        case sessionFailed
        case healthDenied
    }
}
