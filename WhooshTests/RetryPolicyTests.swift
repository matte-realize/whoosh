import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `RetryPolicy` (crash-response task 5, Requirements 12.1,
/// 12.2, 12.5; design "Retry backoff" and "RetryPolicy"). Written test-first.
///
/// Backoff schedule: 5, 15, 30, 60 s, then every 60 s; max 6 attempts for
/// backend failures; the stale-limit check caps auto-send to 30 min from
/// detection.
struct RetryPolicyTests {
    private let tuning = CrashResponseTuning()
    private let detectedAt = Date(timeIntervalSince1970: 1_000_000)

    // MARK: backoff schedule

    @Test func backoffFollowsSchedule() {
        #expect(RetryPolicy.delay(forAttempt: 1, tuning: tuning) == 5)
        #expect(RetryPolicy.delay(forAttempt: 2, tuning: tuning) == 15)
        #expect(RetryPolicy.delay(forAttempt: 3, tuning: tuning) == 30)
        #expect(RetryPolicy.delay(forAttempt: 4, tuning: tuning) == 60)
    }

    @Test func backoffRepeatsLastValueAfterSchedule() {
        #expect(RetryPolicy.delay(forAttempt: 5, tuning: tuning) == 60)
        #expect(RetryPolicy.delay(forAttempt: 6, tuning: tuning) == 60)
        #expect(RetryPolicy.delay(forAttempt: 99, tuning: tuning) == 60)
    }

    @Test func backoffClampsNonPositiveAttemptToFirstDelay() {
        #expect(RetryPolicy.delay(forAttempt: 0, tuning: tuning) == 5)
        #expect(RetryPolicy.delay(forAttempt: -3, tuning: tuning) == 5)
    }

    // MARK: attempt cap

    @Test func attemptsLeftWhileUnderMax() {
        #expect(RetryPolicy.hasAttemptsLeft(afterAttempt: 1, tuning: tuning))
        #expect(RetryPolicy.hasAttemptsLeft(afterAttempt: 5, tuning: tuning))
    }

    @Test func noAttemptsLeftAtMax() {
        // After the 6th attempt there are no more (maxRetryAttempts = 6).
        #expect(!RetryPolicy.hasAttemptsLeft(afterAttempt: 6, tuning: tuning))
        #expect(!RetryPolicy.hasAttemptsLeft(afterAttempt: 7, tuning: tuning))
    }

    // MARK: stale limit

    @Test func withinStaleLimitBeforeThirtyMinutes() {
        let now = detectedAt.addingTimeInterval(29 * 60)
        #expect(RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: now, tuning: tuning))
    }

    @Test func atStaleLimitIsNotWithin() {
        // Exactly 30 min: no longer within (never auto-send after the limit, O3).
        let now = detectedAt.addingTimeInterval(30 * 60)
        #expect(!RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: now, tuning: tuning))
    }

    @Test func pastStaleLimitIsNotWithin() {
        let now = detectedAt.addingTimeInterval(30 * 60 + 1)
        #expect(!RetryPolicy.isWithinStaleLimit(detectedAt: detectedAt, now: now, tuning: tuning))
    }

    // MARK: combined shouldRetry decision

    @Test func shouldRetryWhenAttemptsLeftAndWithinStale() {
        let now = detectedAt.addingTimeInterval(60)
        #expect(RetryPolicy.shouldRetry(afterAttempt: 2, detectedAt: detectedAt, now: now, tuning: tuning))
    }

    @Test func shouldNotRetryWhenAttemptsExhausted() {
        let now = detectedAt.addingTimeInterval(60)
        #expect(!RetryPolicy.shouldRetry(afterAttempt: 6, detectedAt: detectedAt, now: now, tuning: tuning))
    }

    @Test func shouldNotRetryWhenStaleEvenWithAttemptsLeft() {
        let now = detectedAt.addingTimeInterval(31 * 60)
        #expect(!RetryPolicy.shouldRetry(afterAttempt: 1, detectedAt: detectedAt, now: now, tuning: tuning))
    }
}
