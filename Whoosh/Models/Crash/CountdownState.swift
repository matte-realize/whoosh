import Foundation

/// The countdown represented by an **absolute deadline**, never a decrementing
/// counter (spec Requirement 6.8). A missed timer tick, a rebuilt view, a
/// backgrounded app, or a relaunch can therefore never extend or double-fire a
/// countdown: `remaining(at:)` and `isExpired(at:)` are pure functions of the
/// injected clock's `now`.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct CountdownState: Equatable, Codable, Sendable {
    /// The instant at which the countdown expires (clock-based).
    let deadline: Date
    /// The total countdown length in seconds this state was created with
    /// (for display and progress; the deadline is authoritative).
    let totalSeconds: TimeInterval

    init(deadline: Date, totalSeconds: TimeInterval) {
        self.deadline = deadline
        self.totalSeconds = totalSeconds
    }

    /// Seconds remaining until the deadline at `now`, never negative.
    func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    /// Whether the deadline has been reached at `now` (expiry wins ties: the
    /// deadline instant itself counts as expired, per reducer row 9).
    func isExpired(at now: Date) -> Bool {
        now >= deadline
    }
}
