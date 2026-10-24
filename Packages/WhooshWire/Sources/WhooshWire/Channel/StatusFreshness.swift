import Foundation

/// Classifies how fresh the last-received status is on the watch
/// (watch-companion design "`WatchRideReducer`" / "`StatusFreshness`";
/// Requirement 10.4, 10.5, 8.2). Pure value type driven by elapsed
/// milliseconds since the last message (the watch's own monotonic clock — never
/// a phone/watch wall-clock subtraction, design time rule L3).
public struct StatusFreshness: Sendable {
    public let tuning: WatchTuning

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// The freshness classification shown to the rider.
    public enum Level: Equatable, Sendable {
        /// Recent enough to treat as live.
        case fresh
        /// No message for `statusStaleMs`: show "est." elapsed, disable controls.
        case stale
        /// No message for `phoneSilentWarnMs`: "iPhone app may have closed".
        case silent
    }

    /// Classify the freshness given ms since the last received message.
    ///
    /// Staleness only matters while the watch display is active (a dim watch is
    /// expected to go quiet); when the display is off the status is always
    /// treated as fresh so the UI does not flap on a wrist-down watch.
    public func level(msSinceLastMessage: Int, displayActive: Bool) -> Level {
        guard displayActive else { return .fresh }
        if msSinceLastMessage >= tuning.phoneSilentWarnMs { return .silent }
        if msSinceLastMessage >= tuning.statusStaleMs { return .stale }
        return .fresh
    }

    /// Whether controls should be disabled at this freshness (stale or silent
    /// means the phone may not act, so the watch disables within 1 s;
    /// Requirement 6.9, 10.4).
    public func controlsEnabled(msSinceLastMessage: Int, displayActive: Bool) -> Bool {
        level(msSinceLastMessage: msSinceLastMessage, displayActive: displayActive) == .fresh
    }
}
