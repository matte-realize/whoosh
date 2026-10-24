import Foundation

/// Scriptable `CountdownFeedback` for tests and previews that records every
/// `begin`/`tick`/`end` call so the coordinator's feedback sequencing and
/// idempotent-end behaviour can be asserted. Produces no real audio, speech, or
/// haptics.
///
/// Tests reach it via `@testable import`.
final class FakeCountdownFeedback: CountdownFeedback {
    /// Total seconds passed to each `begin`, in call order.
    private(set) var beginTotals: [Int] = []
    /// Remaining values passed to each `tick`, in call order.
    private(set) var tickRemainders: [Int] = []
    /// Reasons passed to each `end`, in call order (even repeated calls).
    private(set) var endReasons: [CountdownFeedbackEndReason] = []

    /// `true` after `begin` and before the first `end`.
    private(set) var isActive = false
    /// Number of `end` calls that actually released feedback (first after a
    /// `begin`); proves idempotency when `end` is called more than once.
    private(set) var effectiveEndCount = 0

    init() {}

    func begin(totalSeconds: Int) {
        beginTotals.append(totalSeconds)
        isActive = true
    }

    func tick(remaining: Int) {
        tickRemainders.append(remaining)
    }

    func end(reason: CountdownFeedbackEndReason) {
        endReasons.append(reason)
        if isActive {
            isActive = false
            effectiveEndCount += 1
        }
    }
}
