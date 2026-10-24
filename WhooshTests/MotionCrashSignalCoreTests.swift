import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `MotionCrashSignalCore` (crash-response task 32,
/// Requirement 5.5/5.6/19.7). Written test-first against synthetic traces:
/// a simulated crash triggers; a pothole, a hard stop, a phone bump/drop while
/// stopped, and ordinary riding do **not**. These are the false-positive guards
/// that justify the (experimental) heuristic; the countdown Cancel is the final
/// safety net.
///
/// Traces are built from plain numbers (user-acceleration magnitude in m/s² with
/// gravity removed, and GPS speed in m/s), so no device or Core Motion is
/// involved and results are deterministic.
struct MotionCrashSignalCoreTests {
    private let tuning = MotionCrashTuning()
    private let g = MotionCrashTuning.gravity
    private let start = Date(timeIntervalSince1970: 1_000)

    // MARK: - Trace helpers

    /// Feed the core a steady acceleration/speed baseline from `t0` for
    /// `duration`, sampling at `hz`, then return the end time.
    @discardableResult
    private func feedSteady(
        _ core: inout MotionCrashSignalCore,
        from t0: Date,
        duration: TimeInterval,
        accelG: Double,
        speed: Double,
        hz: Double = 20
    ) -> Date {
        let step = 1.0 / hz
        var t = t0
        let end = t0.addingTimeInterval(duration)
        while t <= end {
            core.ingest(acceleration: accelG * g, at: t)
            core.ingest(speed: speed, at: t)
            t = t.addingTimeInterval(step)
        }
        return end
    }

    /// Drive `evaluate` once at `now` after feeding a trace.
    private func decide(_ core: inout MotionCrashSignalCore, at now: Date) -> MotionCrashSignalCore.Decision {
        core.evaluate(now: now)
    }

    // MARK: - Simulated crash: triggers

    @Test func simulatedCrashTriggers() {
        var core = MotionCrashSignalCore(tuning: tuning)

        // 3 s of normal riding at ~7 m/s with light motion (~1 g jitter).
        let preEnd = feedSteady(&core, from: start, duration: 3.0, accelG: 1.0, speed: 7.0)

        // A single large impact spike (~6 g).
        let impactTime = preEnd.addingTimeInterval(0.05)
        core.ingest(acceleration: 6.0 * g, at: impactTime)

        // After impact: the rider is down — near-zero speed and near-still phone
        // for the stillness window.
        feedSteady(
            &core,
            from: impactTime.addingTimeInterval(0.1),
            duration: tuning.stillnessWindow + 0.5,
            accelG: 0.05,
            speed: 0.2
        )

        let decision = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay + 0.1))
        guard case let .trigger(confidence, at) = decision else {
            Issue.record("expected a trigger, got \(decision)")
            return
        }
        #expect(confidence >= tuning.triggerScore)
        #expect(at == impactTime)
    }

    // MARK: - Pothole: impact but motion/speed continue -> no trigger

    @Test func potholeDoesNotTrigger() {
        var core = MotionCrashSignalCore(tuning: tuning)
        let preEnd = feedSteady(&core, from: start, duration: 3.0, accelG: 1.0, speed: 7.0)

        // A sharp bump (~5 g) — crosses the impact gate.
        let impactTime = preEnd.addingTimeInterval(0.05)
        core.ingest(acceleration: 5.0 * g, at: impactTime)

        // The rider keeps going: same speed, normal riding motion continues.
        feedSteady(
            &core,
            from: impactTime.addingTimeInterval(0.1),
            duration: tuning.stillnessWindow + 0.5,
            accelG: 1.0,
            speed: 7.0
        )

        let decision = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay + 0.1))
        #expect(decision == .none)
    }

    // MARK: - Hard stop: speed drops but no violent impact -> no trigger

    @Test func hardStopDoesNotTrigger() {
        var core = MotionCrashSignalCore(tuning: tuning)
        let preEnd = feedSteady(&core, from: start, duration: 3.0, accelG: 1.2, speed: 7.0)

        // Braking: speed falls to near zero, but acceleration never spikes past
        // the impact gate (peak stays well under 4 g).
        feedSteady(
            &core,
            from: preEnd.addingTimeInterval(0.05),
            duration: tuning.stillnessWindow + 0.5,
            accelG: 1.5,
            speed: 0.3
        )

        // No impact was gated, so nothing is pending.
        let decision = decide(&core, at: preEnd.addingTimeInterval(tuning.evaluationDelay + 1.0))
        #expect(decision == .none)
    }

    // MARK: - Phone bump/drop while stopped: impact + stillness but no speed -> no trigger

    @Test func phoneBumpWhileStoppedDoesNotTrigger() {
        var core = MotionCrashSignalCore(tuning: tuning)

        // The rider is stopped (speed ~0) and the phone is handled.
        let preEnd = feedSteady(&core, from: start, duration: 2.0, accelG: 1.0, speed: 0.2)

        // A big knock (~6 g) as the phone is bumped or set down.
        let impactTime = preEnd.addingTimeInterval(0.05)
        core.ingest(acceleration: 6.0 * g, at: impactTime)

        // It then sits still.
        feedSteady(
            &core,
            from: impactTime.addingTimeInterval(0.1),
            duration: tuning.stillnessWindow + 0.5,
            accelG: 0.05,
            speed: 0.0
        )

        // No real pre-impact riding speed, so the speed-drop term is zero and the
        // combined score stays below the bar.
        let decision = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay + 0.1))
        #expect(decision == .none)
    }

    // MARK: - Ordinary riding: no impact ever -> no trigger

    @Test func ordinaryRidingNeverTriggers() {
        var core = MotionCrashSignalCore(tuning: tuning)
        // 10 s of normal riding with road jitter well under the impact gate.
        var t = start
        for i in 0..<200 {
            let jitter = 1.0 + 0.8 * Foundation.sin(Double(i) * 0.6) // ~0.2...1.8 g
            core.ingest(acceleration: jitter * g, at: t)
            core.ingest(speed: 6.5, at: t)
            t = t.addingTimeInterval(0.05)
        }
        let decision = decide(&core, at: t.addingTimeInterval(tuning.evaluationDelay))
        #expect(decision == .none)
    }

    // MARK: - Cooldown: one event scores once

    @Test func evaluationIsConsumedSoItDoesNotRepeat() {
        var core = MotionCrashSignalCore(tuning: tuning)
        let preEnd = feedSteady(&core, from: start, duration: 3.0, accelG: 1.0, speed: 7.0)
        let impactTime = preEnd.addingTimeInterval(0.05)
        core.ingest(acceleration: 6.0 * g, at: impactTime)
        feedSteady(
            &core,
            from: impactTime.addingTimeInterval(0.1),
            duration: tuning.stillnessWindow + 0.5,
            accelG: 0.05,
            speed: 0.2
        )

        let first = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay + 0.1))
        if case .trigger = first {} else { Issue.record("expected first evaluation to trigger") }

        // A second evaluate on the same consumed impact yields nothing.
        let second = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay + 0.2))
        #expect(second == .none)
    }

    // MARK: - Evaluation delay: too-early evaluate is inert

    @Test func evaluateBeforeDelayIsNone() {
        var core = MotionCrashSignalCore(tuning: tuning)
        let preEnd = feedSteady(&core, from: start, duration: 1.0, accelG: 1.0, speed: 7.0)
        let impactTime = preEnd.addingTimeInterval(0.05)
        core.ingest(acceleration: 6.0 * g, at: impactTime)

        // Only half the evaluation delay has passed: the windows aren't ready.
        let early = decide(&core, at: impactTime.addingTimeInterval(tuning.evaluationDelay * 0.5))
        #expect(early == .none)
    }

    // MARK: - Tuning sanity

    @Test func thresholdConversionsAreConsistent() {
        #expect(tuning.impactThreshold == tuning.impactThresholdG * g)
        #expect(tuning.stillnessThreshold == tuning.stillnessThresholdG * g)
        // Weights are roughly a partition of unity.
        let sum = tuning.impactWeight + tuning.speedDropWeight + tuning.stillnessWeight
        #expect(abs(sum - 1.0) < 0.001)
    }
}
