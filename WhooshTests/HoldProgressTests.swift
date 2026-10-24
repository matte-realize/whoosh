import Foundation
import Testing
@testable import Whoosh

/// The Stop control's fill must track how long the finger has actually been
/// down, not a fire-and-forget animation (a tap must never look like a stop).
struct HoldProgressTests {
    private static let start = Date(timeIntervalSince1970: 1_000)

    @Test(arguments: [
        (0.0, 0.0),
        (0.25, 0.25),
        (0.5, 0.5),
        (0.999, 0.999),
        (1.0, 1.0),
        (3.0, 1.0),
    ])
    func progressFollowsElapsedHoldTime(elapsed: Double, expected: Double) {
        let now = Self.start.addingTimeInterval(elapsed)
        let progress = HoldProgress.progress(pressStart: Self.start, now: now, holdDuration: 1)
        #expect(abs(progress - expected) < 0.0001)
    }

    @Test func noPressMeansNoProgress() {
        #expect(HoldProgress.progress(pressStart: nil, now: Self.start, holdDuration: 1) == 0)
    }

    @Test func clockGoingBackwardsNeverProducesNegativeProgress() {
        let earlier = Self.start.addingTimeInterval(-5)
        #expect(HoldProgress.progress(pressStart: Self.start, now: earlier, holdDuration: 1) == 0)
    }

    @Test func zeroDurationIsTreatedAsImmediatelyComplete() {
        #expect(HoldProgress.progress(pressStart: Self.start, now: Self.start, holdDuration: 0) == 1)
    }

    @Test func aQuickTapIsNotAStop() {
        let tapEnd = Self.start.addingTimeInterval(0.12)
        #expect(!HoldProgress.isComplete(pressStart: Self.start, now: tapEnd, holdDuration: 1))
    }

    @Test func aFullHoldIsAStop() {
        let holdEnd = Self.start.addingTimeInterval(1.0)
        #expect(HoldProgress.isComplete(pressStart: Self.start, now: holdEnd, holdDuration: 1))
    }
}
