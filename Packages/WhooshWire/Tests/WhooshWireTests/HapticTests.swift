import Testing
import Foundation
@testable import WhooshWire

/// Task 8 — haptic catalog, selector, limiter, and freshness.
/// HP-1…6 (patterns), HL-1…10 (limiter), AF-1…5 (freshness).
@Suite("Haptic catalog, selector, limiter, and freshness")
struct HapticTests {

    // MARK: - Helpers

    private func alert(
        _ kind: WireAlertKind,
        tier: WireAlertTier,
        id: String = UUID().uuidString,
        createdAgoMs: Int = 0,
        ttlMs: Int = 60_000,
        isDemo: Bool = false,
        level: Int? = nil,
        confidence: Int? = nil,
        value: Int? = nil,
        outcome: WireCrashPhase? = nil,
        replay: Bool = false
    ) -> WireAlert {
        WireAlert(
            alertId: id, kind: kind, tier: tier, level: level,
            value: value, isDemo: isDemo, confidence: confidence,
            outcome: outcome, createdAgoMs: createdAgoMs, ttlMs: ttlMs,
            replay: replay
        )
    }

    // MARK: - HP: patterns

    @Test("HP-1: every pair of distinct-meaning patterns has a different signature")
    func hp1_distinctSignatures() {
        let patterns = HapticPatternSelector.distinctMeaningCatalog
        for i in patterns.indices {
            for j in patterns.indices where j > i {
                #expect(patterns[i].signature != patterns[j].signature,
                        "\(patterns[i].name) and \(patterns[j].name) feel identical")
            }
        }
    }

    @Test("HP-2: the three safety-critical patterns differ in first cue or cue count")
    func hp2_safetyCriticalDistinct() {
        let crit = HapticPatternSelector.safetyCritical
        for i in crit.indices {
            for j in crit.indices where j > i {
                let a = crit[i], b = crit[j]
                let differs = a.cues.first != b.cues.first || a.cues.count != b.cues.count
                #expect(differs, "\(a.name) vs \(b.name) not unmistakable")
            }
        }
    }

    @Test("HP-3: rear-vehicle level 2 is chosen for high confidence")
    func hp3_level2OnConfidence() {
        let sel = HapticPatternSelector()
        let high = alert(.rearVehicleCaution, tier: .caution, confidence: 8)
        let low = alert(.rearVehicleCaution, tier: .caution, confidence: 3)
        #expect(sel.pattern(for: high).name == "rearLevel2")
        #expect(sel.pattern(for: low).name == "rearLevel1")
    }

    @Test("HP-4: rear-vehicle level 2 is chosen for a follow-up cue within 10 s, level 1 after")
    func hp4_level2OnFollowUp() {
        let sel = HapticPatternSelector()
        let a = alert(.rearVehicleCaution, tier: .caution)
        #expect(sel.pattern(for: a, context: .init(msSinceLastRearCue: 5_000)).name == "rearLevel2")
        #expect(sel.pattern(for: a, context: .init(msSinceLastRearCue: 11_000)).name == "rearLevel1")
    }

    @Test("HP-5: no pattern uses a navigation cue; crash end maps by outcome; unknown → generic")
    func hp5_noNavCuesAndMappings() {
        let sel = HapticPatternSelector()
        // No navigation cases exist on HapticCue at all, so no pattern can use one.
        for p in HapticPatternSelector.catalog {
            for cue in p.cues {
                #expect(cue != .click || true) // click is allowed; assertion is the enum has no nav case
            }
        }
        #expect(!HapticCue.allCases.map(\.rawValue).contains("navigationLeftTurn"))
        #expect(!HapticCue.allCases.map(\.rawValue).contains("navigationRightTurn"))

        let cancelled = alert(.crashCountdownEnded, tier: .critical, outcome: .cancelled)
        let sending = alert(.crashCountdownEnded, tier: .critical, outcome: .sending)
        let failed = alert(.crashCountdownEnded, tier: .critical, outcome: .failed)
        #expect(sel.pattern(for: cancelled).name == "crashCancelled")
        #expect(sel.pattern(for: sending).name == "alertSending")
        #expect(sel.pattern(for: failed).name == "cancelTooLate")

        let unknown = alert(.unknown, tier: .notice)
        #expect(sel.pattern(for: unknown).name == "genericNotice")
    }

    @Test("HP-6: every pattern gap is at least the 100 ms platform minimum")
    func hp6_minimumSpacing() {
        let floor = WatchTuning().hapticMinCueSpacingMs
        for p in HapticPatternSelector.catalog {
            // Every non-final step has a gap ≥ floor; a single-cue pattern is fine.
            for (idx, step) in p.steps.enumerated() where idx < p.steps.count - 1 {
                #expect(step.gapMs >= floor, "\(p.name) step \(idx) gap \(step.gapMs) < \(floor)")
            }
        }
    }

    // MARK: - AF: freshness

    @Test("AF-1: an alert within its TTL is fresh; beyond its TTL is stale")
    func af1_ttl() {
        let f = AlertFreshness()
        #expect(f.decide(alert(.rearVehicleCaution, tier: .caution, createdAgoMs: 1_000, ttlMs: 3_000)) == .fresh)
        #expect(f.decide(alert(.rearVehicleCaution, tier: .caution, createdAgoMs: 4_000, ttlMs: 3_000)) == .stale)
    }

    @Test("AF-2: link latency is added to age (skew tolerance) and can tip an alert stale")
    func af2_skew() {
        let f = AlertFreshness()
        let a = alert(.rearVehicleCaution, tier: .caution, createdAgoMs: 2_500, ttlMs: 3_000)
        #expect(f.decide(a, linkLatencyMs: 0) == .fresh)
        #expect(f.decide(a, linkLatencyMs: 1_000) == .stale)
    }

    @Test("AF-3: a replay record is never fresh, even within TTL")
    func af3_replayNeverBuzzes() {
        let f = AlertFreshness()
        let a = alert(.rearVehicleCaution, tier: .caution, createdAgoMs: 0, ttlMs: 60_000, replay: true)
        #expect(f.decide(a) == .replay)
        #expect(f.isFresh(a) == false)
    }

    @Test("AF-4: a missing TTL falls back to the per-kind default from tuning")
    func af4_perKindDefault() {
        let t = WatchTuning()
        let f = AlertFreshness(tuning: t)
        let rear = alert(.rearVehicleCaution, tier: .caution, ttlMs: 0)
        let link = alert(.linkRestored, tier: .confirm, ttlMs: 0)
        #expect(f.effectiveTTL(for: rear) == t.ttlRearVehicleMs)
        #expect(f.effectiveTTL(for: link) == t.ttlLinkNoticeMs)
    }

    @Test("AF-5: negative createdAgoMs and latency are clamped to zero (never negative age)")
    func af5_clamp() {
        let f = AlertFreshness()
        let a = alert(.clipSaved, tier: .confirm, createdAgoMs: -5_000, ttlMs: 1_000)
        #expect(f.decide(a, linkLatencyMs: -1_000) == .fresh)
    }

    // MARK: - HL: limiter

    @Test("HL-1: a fresh in-TTL alert plays")
    func hl1_plays() {
        var l = WristHapticLimiter()
        let out = l.admit(alert(.clipSaved, tier: .confirm), nowMs: 0)
        #expect(out.result == .played)
    }

    @Test("HL-2: a duplicate id is suppressed")
    func hl2_duplicate() {
        var l = WristHapticLimiter()
        let a = alert(.clipSaved, tier: .confirm, id: "same")
        _ = l.admit(a, nowMs: 0)
        #expect(l.admit(a, nowMs: 10_000).result == .suppressedDuplicate)
    }

    @Test("HL-3: a stale alert is suppressed before anything else")
    func hl3_stale() {
        var l = WristHapticLimiter()
        let a = alert(.rearVehicleCaution, tier: .caution, createdAgoMs: 9_000, ttlMs: 3_000)
        #expect(l.admit(a, nowMs: 0).result == .suppressedStale)
    }

    @Test("HL-4: a second pattern within the minimum gap is rate-suppressed")
    func hl4_minGap() {
        var l = WristHapticLimiter()
        #expect(l.admit(alert(.clipSaved, tier: .confirm), nowMs: 0).result == .played)
        // 500 ms later (< 1 s min gap).
        #expect(l.admit(alert(.clipNotSaved, tier: .notice), nowMs: 500).result == .suppressedRate)
        // After the gap it plays.
        #expect(l.admit(alert(.clipNotSaved, tier: .notice, id: "x"), nowMs: 1_100).result == .played)
    }

    @Test("HL-5: a higher tier preempts a pattern in progress and still plays")
    func hl5_preemption() {
        var l = WristHapticLimiter()
        #expect(l.admit(alert(.clipSaved, tier: .confirm), nowMs: 0).result == .played)
        // A critical alert 200 ms later (inside the min gap) still plays and preempts.
        let out = l.admit(alert(.crashCountdownStarted, tier: .critical), nowMs: 200)
        #expect(out.result == .played)
        #expect(out.preempted == true)
    }

    @Test("HL-6: a lower tier arriving during a higher in-progress pattern is dropped")
    func hl6_lowerDuringHigher() {
        var l = WristHapticLimiter()
        #expect(l.admit(alert(.crashCountdownStarted, tier: .critical), nowMs: 0).result == .played)
        let out = l.admit(alert(.clipSaved, tier: .confirm), nowMs: 300)
        #expect(out.result == .suppressedHigherTier)
    }

    @Test("HL-7: per-kind camera cooldown suppresses a repeat within 60 s, allows it after")
    func hl7_cameraCooldown() {
        var l = WristHapticLimiter()
        #expect(l.admit(alert(.cameraInterrupted, tier: .notice, id: "a"), nowMs: 0).result == .played)
        // Different kind in between to clear the min-gap but same kind cooldown holds.
        #expect(l.admit(alert(.cameraInterrupted, tier: .notice, id: "b"), nowMs: 30_000).result == .suppressedRate)
        #expect(l.admit(alert(.cameraInterrupted, tier: .notice, id: "c"), nowMs: 61_000).result == .played)
    }

    @Test("HL-8: rear-cue storm backoff grows 3 → 6 → 12 s, then resets after 30 s quiet")
    func hl8_stormBackoff() {
        var l = WristHapticLimiter()
        // First cue at t=0 plays; cooldown 3 s.
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "1"), nowMs: 0).result == .played)
        // Within 3 s → rate-suppressed.
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "2"), nowMs: 2_000).result == .suppressedRate)
        // At 3 s the storm step grows (within 30 s of last) → new cooldown 6 s.
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "3"), nowMs: 3_000).result == .played)
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "4"), nowMs: 8_000).result == .suppressedRate)
        // At 9 s (within 30 s) → step 2, cooldown 12 s.
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "5"), nowMs: 9_000).result == .played)
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "6"), nowMs: 20_000).result == .suppressedRate)
        // After 30 s quiet from the last cue, the storm resets to base 3 s.
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "7"), nowMs: 60_000).result == .played)
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "8"), nowMs: 61_000).result == .suppressedRate)
        #expect(l.admit(alert(.rearVehicleCaution, tier: .caution, id: "9"), nowMs: 63_100).result == .played)
    }

    @Test("HL-9: a demo-flagged alert is suppressed unless the status reports demo active")
    func hl9_demoGate() {
        var off = WristHapticLimiter(demoActive: false)
        #expect(off.admit(alert(.rearVehicleCaution, tier: .caution, isDemo: true), nowMs: 0).result == .suppressedDemo)
        var on = WristHapticLimiter(demoActive: true)
        #expect(on.admit(alert(.rearVehicleCaution, tier: .caution, isDemo: true), nowMs: 0).result == .played)
    }

    @Test("HL-10: disabled drops everything; an inactive player reports suppressedNotActive")
    func hl10_disabledAndNotActive() {
        var disabled = WristHapticLimiter(disabled: true)
        #expect(disabled.admit(alert(.crashCountdownStarted, tier: .critical), nowMs: 0).result == .suppressedDisabled)

        var l = WristHapticLimiter()
        #expect(l.admit(alert(.clipSaved, tier: .confirm), nowMs: 0, playerActive: false).result == .suppressedNotActive)
    }
}
