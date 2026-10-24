import Foundation

/// The full, persistable state of the crash reducer (spec Requirement 6.1–6.3,
/// 6.6, design "Crash event state machine"). A single value type so the whole
/// state is persisted on every transition and a relaunch cannot restart an
/// event. Foundation-only; `Equatable`, `Codable`, `Sendable`.
///
/// - `eventState`: the current `CrashEventState` (`idle` when no event).
/// - `eventId`: the `crashEventId` generated once at detection; the on-wire
///   idempotency key.
/// - `detectedAt`: detection time, used for stale-limit checks across retries.
/// - `isDrill`: a simulated crash uses the `drill` template and does not consume
///   the per-ride cap.
/// - `deadline`: the absolute countdown deadline (Requirement 6.8).
/// - `totalCountdownSeconds`: the clamped length the countdown was created with.
/// - `suppressedUntil`: end of the suppression window after a cancel/send.
/// - `perRideSentCount`: number of *sent* alerts this ride (the cap counts sent
///   only, Owner resolution O2).
/// - `attemptCount`: number of dispatch attempts made for the current event.
/// - `requestInFlight`: whether a dispatch is currently outstanding — a rider
///   "I'm OK" is not cancellable while it is (row 18).
/// - `timeoutRetryUsed`: whether the single O5 unknown-outcome retry was spent.
/// - `outcome`: how the countdown ended, when known.
struct CrashMachineState: Equatable, Codable, Sendable {
    var eventState: CrashEventState
    var eventId: UUID?
    var detectedAt: Date?
    var isDrill: Bool
    var deadline: Date?
    var totalCountdownSeconds: TimeInterval?
    var suppressedUntil: Date?
    var perRideSentCount: Int
    var attemptCount: Int
    var requestInFlight: Bool
    var timeoutRetryUsed: Bool
    var outcome: CountdownOutcome?

    init(
        eventState: CrashEventState = .idle,
        eventId: UUID? = nil,
        detectedAt: Date? = nil,
        isDrill: Bool = false,
        deadline: Date? = nil,
        totalCountdownSeconds: TimeInterval? = nil,
        suppressedUntil: Date? = nil,
        perRideSentCount: Int = 0,
        attemptCount: Int = 0,
        requestInFlight: Bool = false,
        timeoutRetryUsed: Bool = false,
        outcome: CountdownOutcome? = nil
    ) {
        self.eventState = eventState
        self.eventId = eventId
        self.detectedAt = detectedAt
        self.isDrill = isDrill
        self.deadline = deadline
        self.totalCountdownSeconds = totalCountdownSeconds
        self.suppressedUntil = suppressedUntil
        self.perRideSentCount = perRideSentCount
        self.attemptCount = attemptCount
        self.requestInFlight = requestInFlight
        self.timeoutRetryUsed = timeoutRetryUsed
        self.outcome = outcome
    }

    /// The resting/idle starting state for a new ride.
    static let initial = CrashMachineState()

    /// Whether a suppression window is active at `now`.
    func isSuppressed(at now: Date) -> Bool {
        guard let suppressedUntil else { return false }
        return now < suppressedUntil
    }
}
