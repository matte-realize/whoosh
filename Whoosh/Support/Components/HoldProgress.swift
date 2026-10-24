import Foundation

/// Pure timing for the press-and-hold Stop control: progress is derived from
/// when the finger went down, so the fill tracks the real hold and a tap can
/// never look like (or count as) a completed stop.
nonisolated enum HoldProgress {
    /// Fraction of the hold completed, clamped to `0...1`; `0` when not pressed.
    static func progress(pressStart: Date?, now: Date, holdDuration: TimeInterval) -> Double {
        guard let pressStart else { return 0 }
        guard holdDuration > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(pressStart)
        return min(max(elapsed / holdDuration, 0), 1)
    }

    /// Whether the hold has lasted the full duration.
    static func isComplete(pressStart: Date?, now: Date, holdDuration: TimeInterval) -> Bool {
        progress(pressStart: pressStart, now: now, holdDuration: holdDuration) >= 1
    }
}
