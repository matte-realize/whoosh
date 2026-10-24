import Foundation

/// Pure retry/stale policy for queued or failed crash-alert sends (spec
/// Requirements 12.1, 12.2, 12.5; design "Retry backoff" and Owner resolution
/// O3). Pure, framework-free (Metrics layer), static functions.
///
/// Backoff schedule 5, 15, 30, 60 s then every 60 s; at most
/// `maxRetryAttempts` (6) attempts for backend failures; and after the stale
/// limit (30 min from detection) an alert is **never** auto-sent (O3). The
/// coordinator composes these with the same `crashEventId` across retries.
enum RetryPolicy {
    /// Backoff delay before a 1-based attempt number. Attempts ≤ 0 clamp to the
    /// first delay. Delegates to `CrashResponseTuning.backoffDelay(forAttempt:)`.
    static func delay(forAttempt attempt: Int, tuning: CrashResponseTuning) -> TimeInterval {
        tuning.backoffDelay(forAttempt: max(1, attempt))
    }

    /// Whether another attempt is allowed after `attempt` attempts have been
    /// made, by the attempt cap alone (ignores staleness). `attempt` is the
    /// count of attempts already completed.
    static func hasAttemptsLeft(afterAttempt attempt: Int, tuning: CrashResponseTuning) -> Bool {
        attempt < tuning.maxRetryAttempts
    }

    /// Whether `now` is still within the stale limit measured from `detectedAt`
    /// (strictly before the limit; at or past it is stale, O3).
    static func isWithinStaleLimit(
        detectedAt: Date,
        now: Date,
        tuning: CrashResponseTuning
    ) -> Bool {
        tuning.isWithinStaleLimit(detectedAt: detectedAt, now: now)
    }

    /// The combined decision: retry only when attempts remain **and** the event
    /// is still within the stale limit.
    static func shouldRetry(
        afterAttempt attempt: Int,
        detectedAt: Date,
        now: Date,
        tuning: CrashResponseTuning
    ) -> Bool {
        hasAttemptsLeft(afterAttempt: attempt, tuning: tuning)
            && isWithinStaleLimit(detectedAt: detectedAt, now: now, tuning: tuning)
    }
}
