import Foundation

/// The debounce rule for repeated rear-vehicle cues (an experimental feature):
/// a burst of alert fires inside a short window collapses to a single cue so the
/// rider is not buzzed continuously.
///
/// Pure, framework-free (Metrics layer: Foundation only), so it is unit-tested
/// deterministically without any haptic or audio hardware. `HapticAudioAlertManager`
/// (in `Services/Alerts/`) consults this rule through the injected `Clock` before
/// doing any work.
///
/// The cue is an *experimental* assistance signal, not a reliable detector; the
/// debounce only governs how often the cue is surfaced.
enum AlertCooldown {
    /// The default minimum gap between surfaced rear-vehicle cues.
    static let defaultCooldownSeconds: TimeInterval = 2

    /// Whether a new cue should fire now, given when the last cue fired.
    ///
    /// - A `nil` `lastFiredAt` (no prior cue) always fires.
    /// - A non-positive `cooldown` disables debouncing (always fires).
    /// - Otherwise the cue fires only once strictly more than `cooldown`
    ///   seconds have elapsed since the last cue. A `now` at or before the last
    ///   fire (including clock skew going backwards) is treated as still inside
    ///   the window and is suppressed.
    static func shouldFire(
        lastFiredAt: Date?,
        now: Date,
        cooldown: TimeInterval = defaultCooldownSeconds
    ) -> Bool {
        guard cooldown > 0 else { return true }
        guard let lastFiredAt else { return true }
        return now.timeIntervalSince(lastFiredAt) > cooldown
    }
}
