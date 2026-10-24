import Foundation

/// The pure rate-limiter and gate for wrist haptics (watch-companion design
/// "`WristHapticLimiter` and `AlertFreshness`"; Requirement 12.1–12.5, 12.7).
///
/// Given an alert and the monotonic watch time (`nowMs`), it decides whether
/// the alert may buzz and returns a `WireAlertReceiptResult`. It is a value type
/// the caller advances with `mutating func admit`; it keeps only small state
/// (last-play time, last tier in progress, per-kind cooldown times, seen ids,
/// storm state). All times are the watch's own monotonic clock in ms — no
/// wall-clock subtraction (design time rule L3).
///
/// Order of checks (design table):
/// 1. disabled → `suppressedDisabled`
/// 2. demo-flagged while status is not demo → `suppressedDemo`
/// 3. freshness (`AlertFreshness`) → `suppressedStale`
/// 4. duplicate id → `suppressedDuplicate`
/// 5. tier preemption (lower tier during a higher in-progress) → `suppressedHigherTier`
/// 6. minimum gap / per-kind cooldown (with storm backoff) → `suppressedRate`
/// Otherwise → `played` (and the in-progress pattern of lower tiers is preempted).
public struct WristHapticLimiter: Sendable {
    public let tuning: WatchTuning
    private let freshness: AlertFreshness

    /// Whether the rider has turned watch haptics off.
    public var disabled: Bool
    /// Whether the latest phone status reports demo mode active.
    public var demoActive: Bool
    /// When true, rear cues skip their per-kind cooldown and storm backoff and
    /// keep only the minimum gap, so a car closing in dings faster. The phone
    /// still paces real-ride rear cues (3 s); only its urgent proximity path
    /// sends them faster.
    public var rapidRearCues = false

    // In-progress pattern state (for preemption and minimum gap).
    private var lastPlayMs: Int?
    private var inProgressTier: WireAlertTier?
    /// When the in-progress pattern is expected to end (for preemption of a
    /// lower tier *while* a higher one plays). We treat a pattern as "in
    /// progress" for `minGap`.
    private var inProgressUntilMs: Int?

    // Dedupe.
    private var seenIds: Set<String> = []

    // Per-kind cooldown: next time each kind may play again.
    private var cooldownUntil: [WireAlertKind: Int] = [:]

    // Storm backoff for the rear cue.
    private var rearStormStep = 0          // 0 → 3 s, 1 → 6 s, 2+ → 12 s
    private var lastRearCueMs: Int?

    public init(
        tuning: WatchTuning = WatchTuning(),
        disabled: Bool = false,
        demoActive: Bool = false
    ) {
        self.tuning = tuning
        self.freshness = AlertFreshness(tuning: tuning)
        self.disabled = disabled
        self.demoActive = demoActive
    }

    /// The result of attempting to admit an alert.
    public struct Outcome: Equatable, Sendable {
        public var result: WireAlertReceiptResult
        /// True when a higher-tier alert preempted a pattern already playing.
        public var preempted: Bool

        public init(result: WireAlertReceiptResult, preempted: Bool = false) {
            self.result = result
            self.preempted = preempted
        }
    }

    /// Decide whether `alert` may buzz at monotonic `nowMs`, updating state.
    /// `linkLatencyMs` feeds the freshness check; `playerActive` reflects the
    /// `HapticPlaying.isActive` fact (false → `suppressedNotActive`).
    public mutating func admit(
        _ alert: WireAlert,
        nowMs: Int,
        linkLatencyMs: Int = 0,
        playerActive: Bool = true
    ) -> Outcome {
        // 1. Disabled gate.
        if disabled { return Outcome(result: .suppressedDisabled) }

        // 2. Demo gate: a demo alert only plays while the phone reports demo.
        if alert.isDemo && !demoActive { return Outcome(result: .suppressedDemo) }

        // 3. Freshness.
        switch freshness.decide(alert, linkLatencyMs: linkLatencyMs) {
        case .replay, .stale:
            return Outcome(result: .suppressedStale)
        case .fresh:
            break
        }

        // 4. Duplicate id.
        if seenIds.contains(alert.alertId) {
            return Outcome(result: .suppressedDuplicate)
        }

        // 5. Player not active.
        if !playerActive {
            // Record the id so a later retry of the same alert is a duplicate.
            seenIds.insert(alert.alertId)
            return Outcome(result: .suppressedNotActive)
        }

        let tier = alert.tier
        let higherInProgress = isPatternInProgress(nowMs: nowMs)
            && rank(of: inProgressTier) > rank(of: tier)
        // A lower tier arriving while a higher one is in progress is dropped.
        if higherInProgress {
            seenIds.insert(alert.alertId)
            return Outcome(result: .suppressedHigherTier)
        }

        // Whether this admission preempts a lower-tier pattern in progress.
        let preempts = isPatternInProgress(nowMs: nowMs)
            && rank(of: tier) > rank(of: inProgressTier)

        // 6. Minimum gap and per-kind cooldown — skipped only when a `critical`
        // alert arrives (crash always buzzes; design: min gap "except
        // preemption by `critical`").
        if tier != .critical {
            // Minimum gap between pattern starts.
            if let last = lastPlayMs, nowMs - last < tuning.hapticMinGapMs {
                return Outcome(result: .suppressedRate)
            }
            // Per-kind cooldown (rear cue uses storm backoff).
            let skipCooldown = rapidRearCues && alert.kind == .rearVehicleCaution
            if !skipCooldown, let until = cooldownUntil[alert.kind], nowMs < until {
                return Outcome(result: .suppressedRate)
            }
        }

        // Admitted. Record state.
        admitState(alert, nowMs: nowMs)
        return Outcome(result: .played, preempted: preempts)
    }

    // MARK: - State updates on admission

    private mutating func admitState(_ alert: WireAlert, nowMs: Int) {
        seenIds.insert(alert.alertId)
        lastPlayMs = nowMs
        inProgressTier = alert.tier
        inProgressUntilMs = nowMs + tuning.hapticMinGapMs

        // Per-kind cooldown.
        switch alert.kind {
        case .rearVehicleCaution:
            updateRearStorm(nowMs: nowMs)
            cooldownUntil[alert.kind] = nowMs + rearCooldownMs()
            lastRearCueMs = nowMs
        case .cameraInterrupted, .cameraResumed, .cameraStopped:
            cooldownUntil[alert.kind] = nowMs + tuning.cameraNoticeCooldownMs
        default:
            break
        }
    }

    private mutating func updateRearStorm(nowMs: Int) {
        if let last = lastRearCueMs, nowMs - last <= tuning.stormResetMs {
            rearStormStep = min(rearStormStep + 1, 2)
        } else {
            rearStormStep = 0
        }
    }

    /// Current rear-cue cooldown: 3 → 6 → 12 s (base × 1,2,4).
    private func rearCooldownMs() -> Int {
        let base = tuning.rearCueCooldownMs
        switch rearStormStep {
        case 0: return base
        case 1: return base * 2
        default: return base * 4
        }
    }

    private func isPatternInProgress(nowMs: Int) -> Bool {
        guard let until = inProgressUntilMs else { return false }
        return nowMs < until
    }

    /// Tier ordering: critical > caution > notice > confirm.
    private func rank(of tier: WireAlertTier?) -> Int {
        switch tier {
        case .critical: return 4
        case .caution: return 3
        case .notice: return 2
        case .confirm: return 1
        case .unknown, .none: return 0
        }
    }
}
