import Foundation
import Testing
@testable import Whoosh

/// Repeated rear-vehicle cues must not stack: a burst of fires inside a short
/// window should surface at most one cue so the rider isn't buzzed continuously.
/// The debounce rule is a pure function of "when did the last cue fire" and
/// "what time is it now", so it is fully unit-testable without any hardware.
struct AlertCooldownTests {
    private static let window: TimeInterval = 2
    private static let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstFireIsAlwaysAllowed() {
        #expect(AlertCooldown.shouldFire(lastFiredAt: nil, now: Self.start, cooldown: Self.window))
    }

    @Test func aSecondFireInsideTheWindowIsSuppressed() {
        let soon = Self.start.addingTimeInterval(0.5)
        #expect(!AlertCooldown.shouldFire(lastFiredAt: Self.start, now: soon, cooldown: Self.window))
    }

    @Test func aFireExactlyAtTheWindowBoundaryIsSuppressed() {
        let boundary = Self.start.addingTimeInterval(Self.window)
        // At exactly `cooldown` seconds the window has not yet fully elapsed.
        #expect(!AlertCooldown.shouldFire(lastFiredAt: Self.start, now: boundary, cooldown: Self.window))
    }

    @Test func aFireAfterTheWindowIsAllowed() {
        let later = Self.start.addingTimeInterval(Self.window + 0.001)
        #expect(AlertCooldown.shouldFire(lastFiredAt: Self.start, now: later, cooldown: Self.window))
    }

    @Test func aBurstInsideTheWindowCollapsesToOne() {
        // Simulate repeated fires driven off a single "last fired" instant.
        var lastFired: Date?
        var allowedCount = 0
        for offset in stride(from: 0.0, through: 1.8, by: 0.2) {
            let now = Self.start.addingTimeInterval(offset)
            if AlertCooldown.shouldFire(lastFiredAt: lastFired, now: now, cooldown: Self.window) {
                allowedCount += 1
                lastFired = now
            }
        }
        #expect(allowedCount == 1)
    }

    @Test func twoBurstsSeparatedByTheWindowProduceTwoCues() {
        var lastFired: Date?
        var allowedCount = 0
        // First burst around t=0, second burst after the window has elapsed.
        for offset in [0.0, 0.3, 0.6, 2.5, 2.7, 3.0] {
            let now = Self.start.addingTimeInterval(offset)
            if AlertCooldown.shouldFire(lastFiredAt: lastFired, now: now, cooldown: Self.window) {
                allowedCount += 1
                lastFired = now
            }
        }
        #expect(allowedCount == 2)
    }

    @Test func aNonPositiveCooldownNeverSuppresses() {
        let soon = Self.start.addingTimeInterval(0.0001)
        #expect(AlertCooldown.shouldFire(lastFiredAt: Self.start, now: soon, cooldown: 0))
        #expect(AlertCooldown.shouldFire(lastFiredAt: Self.start, now: soon, cooldown: -1))
    }

    @Test func aClockThatGoesBackwardsStillSuppressesWithinTheWindow() {
        // Defensive: if `now` precedes the last fire (clock skew), treat it as
        // still inside the window rather than firing again.
        let earlier = Self.start.addingTimeInterval(-5)
        #expect(!AlertCooldown.shouldFire(lastFiredAt: Self.start, now: earlier, cooldown: Self.window))
    }
}
