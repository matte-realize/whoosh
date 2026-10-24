import Foundation

/// All crash-response tuning constants in one place (spec `design.md`
/// "CrashResponseTuning"), so values are never hard-coded at call sites.
///
/// Foundation-only value type (Models layer). `Codable` so a persisted event
/// can carry the tuning it was created under if that is ever needed; `Equatable`
/// and `Sendable` so it can cross actors and be compared in tests.
///
/// Documented defaults and ranges:
/// - `countdownSeconds`: 30 s default, clamped to 15–60 s by `clampCountdown`.
/// - `suppressionWindow`: 120 s after a cancel or a send; new signals ignored.
/// - `maxAutomaticAlertsPerRide`: 1 — counts *sent* alerts only; a cancelled
///   countdown does not consume the cap.
/// - `maxContacts`: 3 — cost/abuse control.
/// - `staleLimit`: 30 min from detection; after it, never auto-send.
/// - `retryBackoff` + `maxRetryAttempts`: 5, 15, 30, 60 s then every 60 s, up to
///   6 attempts for backend failures.
/// - `maxLocationAge`: 30 min; older fixes are treated as unavailable.
/// - `currentFixMaxAge`: ≤ 10 s counts as the "current" location.
/// - `requestTimeout`: 10 s per notifier call.
/// - `localRecordRetention`: 90 days; the rider can delete sooner.
/// - `maxRiderLabelLength`: 20 (GSM-7-safe charset).
/// - `testCooldownPerContact`: 60 s per contact (client mirror; backend
///   authoritative).
/// - `messageSegmentCap` / `messageCharacterCap`: ≤ 4 segments / ≤ 612 chars.
struct CrashResponseTuning: Equatable, Codable, Sendable {
    var countdownSeconds: TimeInterval = 30
    var minCountdownSeconds: TimeInterval = 15
    var maxCountdownSeconds: TimeInterval = 60
    var suppressionWindow: TimeInterval = 120
    var maxAutomaticAlertsPerRide: Int = 1
    var maxContacts: Int = 3
    var staleLimit: TimeInterval = 30 * 60
    var maxLocationAge: TimeInterval = 30 * 60
    var currentFixMaxAge: TimeInterval = 10
    var requestTimeout: TimeInterval = 10
    var localRecordRetention: TimeInterval = 90 * 24 * 60 * 60
    var maxRiderLabelLength: Int = 20
    var testCooldownPerContact: TimeInterval = 60
    /// Backoff delays in seconds; after the last entry, repeat the last value.
    var retryBackoff: [TimeInterval] = [5, 15, 30, 60]
    var maxRetryAttempts: Int = 6
    var messageSegmentCap: Int = 4
    var messageCharacterCap: Int = 612

    init(
        countdownSeconds: TimeInterval = 30,
        minCountdownSeconds: TimeInterval = 15,
        maxCountdownSeconds: TimeInterval = 60,
        suppressionWindow: TimeInterval = 120,
        maxAutomaticAlertsPerRide: Int = 1,
        maxContacts: Int = 3,
        staleLimit: TimeInterval = 30 * 60,
        maxLocationAge: TimeInterval = 30 * 60,
        currentFixMaxAge: TimeInterval = 10,
        requestTimeout: TimeInterval = 10,
        localRecordRetention: TimeInterval = 90 * 24 * 60 * 60,
        maxRiderLabelLength: Int = 20,
        testCooldownPerContact: TimeInterval = 60,
        retryBackoff: [TimeInterval] = [5, 15, 30, 60],
        maxRetryAttempts: Int = 6,
        messageSegmentCap: Int = 4,
        messageCharacterCap: Int = 612
    ) {
        self.countdownSeconds = countdownSeconds
        self.minCountdownSeconds = minCountdownSeconds
        self.maxCountdownSeconds = maxCountdownSeconds
        self.suppressionWindow = suppressionWindow
        self.maxAutomaticAlertsPerRide = maxAutomaticAlertsPerRide
        self.maxContacts = maxContacts
        self.staleLimit = staleLimit
        self.maxLocationAge = maxLocationAge
        self.currentFixMaxAge = currentFixMaxAge
        self.requestTimeout = requestTimeout
        self.localRecordRetention = localRecordRetention
        self.maxRiderLabelLength = maxRiderLabelLength
        self.testCooldownPerContact = testCooldownPerContact
        self.retryBackoff = retryBackoff
        self.maxRetryAttempts = maxRetryAttempts
        self.messageSegmentCap = messageSegmentCap
        self.messageCharacterCap = messageCharacterCap
    }

    /// Clamp a requested countdown length to the allowed 15–60 s range.
    func clampCountdown(_ requested: TimeInterval) -> TimeInterval {
        min(max(requested, minCountdownSeconds), maxCountdownSeconds)
    }

    /// Backoff delay for a 1-based attempt number: 5, 15, 30, 60, then 60…
    func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1, !retryBackoff.isEmpty else { return retryBackoff.last ?? 60 }
        let index = min(attempt - 1, retryBackoff.count - 1)
        return retryBackoff[index]
    }

    /// Whether `now` is still within the stale limit measured from `detectedAt`.
    func isWithinStaleLimit(detectedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(detectedAt) < staleLimit
    }
}
