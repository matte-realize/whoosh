import Foundation
@testable import Whoosh

/// Deterministic `Clock` for tests. Time only moves when a test calls
/// `advance(by:)` (or sets `currentTime`), and scheduled work fires exactly when
/// the virtual clock passes its due instant — no real waiting, no flakiness.
///
/// Lives in the test target (test support); the app ships `SystemClock`.
final class TestClock: Clock {
    private(set) var currentTime: Date
    private var scheduled: [ScheduledWork] = []
    private var nextID = 0

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.currentTime = now
    }

    func now() -> Date { currentTime }

    @discardableResult
    func schedule(
        after interval: TimeInterval,
        _ work: @escaping () -> Void
    ) -> Cancellable {
        let id = nextID
        nextID += 1
        let fireAt = currentTime.addingTimeInterval(interval)
        scheduled.append(ScheduledWork(id: id, fireAt: fireAt, work: work))
        return Token(clock: self, id: id)
    }

    /// Advance virtual time by `interval`, firing any scheduled work whose due
    /// instant is now at or before the new current time, in due-time order.
    func advance(by interval: TimeInterval) {
        let target = currentTime.addingTimeInterval(interval)
        while let next = scheduled
            .filter({ $0.fireAt <= target })
            .min(by: { $0.fireAt < $1.fireAt }) {
            // Move time to the work's due instant before running it.
            currentTime = next.fireAt
            scheduled.removeAll { $0.id == next.id }
            next.work()
        }
        currentTime = target
    }

    /// Number of still-pending (uncancelled, unfired) scheduled items.
    var pendingCount: Int { scheduled.count }

    fileprivate func cancel(id: Int) {
        scheduled.removeAll { $0.id == id }
    }

    private struct ScheduledWork {
        let id: Int
        let fireAt: Date
        let work: () -> Void
    }

    private struct Token: Cancellable {
        weak var clock: TestClock?
        let id: Int
        func cancel() { clock?.cancel(id: id) }
    }
}
