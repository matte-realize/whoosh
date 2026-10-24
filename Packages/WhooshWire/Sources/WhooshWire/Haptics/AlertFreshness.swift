import Foundation

/// Decides whether a `WireAlert` is fresh enough to buzz (watch-companion
/// design "`WristHapticLimiter` and `AlertFreshness`"; Requirement 12.4, 12.7).
/// Pure: `age = createdAgoMs + linkLatencyMs` (skew-free; both values are
/// relative, never wall-clock subtracted), and an alert is stale when its age
/// exceeds its TTL. A `replay` record (reconnect fill-in) is **never** fresh —
/// it is logged but must never buzz.
///
/// The alert carries its own `ttlMs`; when it is missing or non-positive the
/// per-kind default from `WatchTuning` is used so an older phone that omits a
/// TTL still gets a sensible cutoff.
public struct AlertFreshness: Sendable {
    public let tuning: WatchTuning

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    public enum Decision: Equatable, Sendable {
        case fresh
        /// Beyond its TTL; the watch logs it but does not buzz.
        case stale
        /// A replay/log-only record; never buzzes.
        case replay
    }

    /// Classify `alert` given the measured one-way link latency (ms, ≥ 0).
    public func decide(_ alert: WireAlert, linkLatencyMs: Int = 0) -> Decision {
        if alert.replay { return .replay }
        let ttl = effectiveTTL(for: alert)
        let age = max(0, alert.createdAgoMs) + max(0, linkLatencyMs)
        return age > ttl ? .stale : .fresh
    }

    /// Convenience boolean (true only for `.fresh`).
    public func isFresh(_ alert: WireAlert, linkLatencyMs: Int = 0) -> Bool {
        decide(alert, linkLatencyMs: linkLatencyMs) == .fresh
    }

    /// The TTL in ms for `alert`: its own `ttlMs` if positive, else the per-kind
    /// default from tuning.
    public func effectiveTTL(for alert: WireAlert) -> Int {
        if alert.ttlMs > 0 { return alert.ttlMs }
        return defaultTTL(for: alert.kind)
    }

    func defaultTTL(for kind: WireAlertKind) -> Int {
        switch kind {
        case .rearVehicleCaution:
            return tuning.ttlRearVehicleMs
        case .clipSaved, .clipNotSaved:
            return tuning.ttlClipNoticeMs
        case .cameraInterrupted, .cameraResumed, .cameraStopped, .phoneBatteryLow:
            return tuning.ttlCameraBatteryMs
        case .linkRestored:
            return tuning.ttlLinkNoticeMs
        case .crashCountdownStarted, .crashCountdownEnded:
            // Crash cues are critical and effectively never aged out by
            // freshness; use the widest camera/battery TTL as a floor.
            return max(tuning.ttlCameraBatteryMs, tuning.ttlLinkNoticeMs)
        case .hapticTest, .patternPreview, .unknown:
            return tuning.ttlCameraBatteryMs
        }
    }
}
