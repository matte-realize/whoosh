import Foundation
import Testing
@testable import Whoosh

/// Tests for the `Clock` seam via `TestClock` (Requirement 4.6 — testable timing
/// foundation). These prove scheduled work fires after the interval and that
/// cancellation prevents it, so the signal-loss timer in the ride engine can be
/// driven deterministically.
struct ClockTests {
    @Test func nowReflectsInitialTimeAndAdvances() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(now: start)
        #expect(clock.now() == start)
        clock.advance(by: 30)
        #expect(clock.now() == start.addingTimeInterval(30))
    }

    @Test func scheduledWorkDoesNotFireBeforeInterval() {
        let clock = TestClock()
        var fired = false
        clock.schedule(after: 10) { fired = true }
        clock.advance(by: 9)
        #expect(fired == false)
    }

    @Test func scheduledWorkFiresAfterAdvancingPastInterval() {
        let clock = TestClock()
        var fired = false
        clock.schedule(after: 10) { fired = true }
        clock.advance(by: 10)
        #expect(fired == true)
    }

    @Test func scheduledWorkFiresWhenAdvancingWellPastInterval() {
        let clock = TestClock()
        var fireCount = 0
        clock.schedule(after: 5) { fireCount += 1 }
        clock.advance(by: 100)
        #expect(fireCount == 1)
    }

    @Test func cancelPreventsScheduledWork() {
        let clock = TestClock()
        var fired = false
        let token = clock.schedule(after: 10) { fired = true }
        token.cancel()
        clock.advance(by: 20)
        #expect(fired == false)
        #expect(clock.pendingCount == 0)
    }

    @Test func multipleScheduledWorksFireInDueOrder() {
        let clock = TestClock()
        var order: [Int] = []
        clock.schedule(after: 30) { order.append(3) }
        clock.schedule(after: 10) { order.append(1) }
        clock.schedule(after: 20) { order.append(2) }
        clock.advance(by: 30)
        #expect(order == [1, 2, 3])
    }

    @Test func workScheduledAtFireTimeSeesUpdatedClock() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(now: start)
        var observed: Date?
        clock.schedule(after: 15) { observed = clock.now() }
        clock.advance(by: 50)
        #expect(observed == start.addingTimeInterval(15))
    }
}
