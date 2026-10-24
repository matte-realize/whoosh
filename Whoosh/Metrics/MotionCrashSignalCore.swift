import Foundation

/// The **pure, framework-free** signal-processing core of the experimental
/// motion crash detector (crash-response task 32, Requirement 5.5/5.6/19.7).
///
/// Lives in the Metrics layer (Foundation only — no Core Motion, no Core
/// Location). The `MotionCrashDetector` adapter (task 33) reads the Core Motion
/// device-motion stream and `RideContext` and feeds this core plain numbers;
/// everything that decides whether a trace looks like a crash is here, so it is
/// unit-testable against synthetic and recorded traces with no device.
///
/// ## Heuristic (see `MotionCrashTuning` for the thresholds and the rationale)
/// A probable crash is a **short, large acceleration spike** (the impact),
/// followed by a **large GPS speed drop** and **unusual stillness**. The impact
/// is the *gate*: no impact ⇒ no evaluation ever. When an impact is seen, the
/// core schedules an evaluation `evaluationDelay` later; at evaluation it scores
/// the speed drop and stillness over their windows, combines all three terms
/// into `0...1`, and reports a trigger when the score ≥ `triggerScore`.
///
/// This conservative design means common non-crash events do **not** trigger:
/// - a pothole spikes acceleration but speed and motion continue (no speed drop,
///   no stillness),
/// - a hard stop drops speed but has no violent spike (no impact gate),
/// - bumping or dropping the phone while stopped had no real pre-impact speed
///   (speed-drop term is zero and gated by `minPreImpactSpeed`).
///
/// ## Usage (driven by the adapter, deterministic in tests)
/// 1. `ingest(acceleration:at:)` for each motion sample (user-acceleration
///    magnitude in m/s², gravity already removed, with the sample time).
/// 2. `ingest(speed:at:)` for each accepted GPS speed (m/s) with its time.
/// 3. `evaluate(now:)` periodically (the adapter ticks it). It returns a
///    `Decision`: `.none` normally, or `.trigger(confidence:at:)` once, when an
///    impact's evaluation time has arrived and the score clears the bar. After a
///    trigger (or a non-triggering evaluation) a `cooldown` prevents re-scoring
///    the same event.
///
/// A `struct` with value semantics; the adapter owns one instance on its
/// processing queue and mutates it in place. No reference types, no shared state.
struct MotionCrashSignalCore {
    /// The result of an `evaluate(now:)` call.
    enum Decision: Equatable {
        /// Nothing to report yet.
        case none
        /// A probable crash: combined confidence `0...1` and the impact instant.
        case trigger(confidence: Double, at: Date)
    }

    let tuning: MotionCrashTuning

    /// Recent acceleration samples, trimmed to the longest window we need.
    private var accelSamples: [TimedValue] = []
    /// Recent speed samples, trimmed similarly.
    private var speedSamples: [TimedValue] = []

    /// The most recent impact that is awaiting evaluation, if any.
    private var pendingImpact: Impact?
    /// Until this time, new impacts are ignored (one event scores once). `nil`
    /// means no cooldown is active.
    private var cooldownUntil: Date?

    init(tuning: MotionCrashTuning = MotionCrashTuning()) {
        self.tuning = tuning
    }

    // MARK: - Ingest

    /// Feed one acceleration magnitude sample (user acceleration, gravity
    /// removed, m/s²). Detects the impact gate and starts a pending evaluation.
    mutating func ingest(acceleration magnitude: Double, at time: Date) {
        accelSamples.append(TimedValue(time: time, value: magnitude))
        trim(&accelSamples, keeping: longestLookback, before: time)

        // Impact gate: a magnitude over threshold, outside any cooldown, and not
        // already tracking a pending impact, starts an evaluation.
        if magnitude >= tuning.impactThreshold,
           !isInCooldown(at: time),
           pendingImpact == nil {
            pendingImpact = Impact(
                time: time,
                peak: magnitude,
                preImpactSpeed: speed(at: time)
            )
        } else if var impact = pendingImpact, magnitude > impact.peak,
                  time.timeIntervalSince(impact.time) <= tuning.impactWindow {
            // Track the strongest peak within the impact window.
            impact.peak = magnitude
            pendingImpact = impact
        }
    }

    /// Feed one accepted GPS speed sample (m/s).
    mutating func ingest(speed value: Double, at time: Date) {
        speedSamples.append(TimedValue(time: time, value: value))
        trim(&speedSamples, keeping: longestLookback, before: time)
    }

    // MARK: - Evaluate

    /// Evaluate at `now`. Returns `.trigger` at most once per impact, when the
    /// evaluation delay has elapsed and the combined score clears the bar;
    /// otherwise `.none`. Always clears the pending impact once its evaluation
    /// time has arrived (and opens the cooldown), so a non-triggering event does
    /// not linger.
    mutating func evaluate(now: Date) -> Decision {
        guard let impact = pendingImpact else { return .none }
        guard now.timeIntervalSince(impact.time) >= tuning.evaluationDelay else {
            return .none
        }

        let score = score(for: impact)

        // Consume the impact and open the cooldown regardless of the outcome.
        pendingImpact = nil
        cooldownUntil = impact.time.addingTimeInterval(tuning.cooldown)

        if score >= tuning.triggerScore {
            return .trigger(confidence: score, at: impact.time)
        }
        return .none
    }

    // MARK: - Scoring

    /// Combined `0...1` score for an impact: a gating impact term plus the
    /// speed-drop and stillness corroboration terms, each in `0...1`, weighted.
    private func score(for impact: Impact) -> Double {
        let impactTerm = impactTerm(peak: impact.peak)
        // The impact is a gate: if it is zero the whole score is zero.
        guard impactTerm > 0 else { return 0 }

        let speedTerm = speedDropTerm(preImpactSpeed: impact.preImpactSpeed, impactTime: impact.time)
        let stillTerm = stillnessTerm(impactTime: impact.time)

        let weighted =
            impactTerm * tuning.impactWeight +
            speedTerm * tuning.speedDropWeight +
            stillTerm * tuning.stillnessWeight
        let totalWeight = tuning.impactWeight + tuning.speedDropWeight + tuning.stillnessWeight
        guard totalWeight > 0 else { return 0 }
        return min(1.0, max(0.0, weighted / totalWeight))
    }

    /// Impact term in `0...1`: 0 below threshold, ramping to 1 at ~2× threshold.
    private func impactTerm(peak: Double) -> Double {
        guard peak >= tuning.impactThreshold else { return 0 }
        let over = (peak - tuning.impactThreshold) / tuning.impactThreshold
        return min(1.0, 0.5 + 0.5 * over)
    }

    /// Speed-drop term in `0...1`. Needs a real pre-impact speed (≥
    /// `minPreImpactSpeed`); scores how far the post-impact speed fell relative
    /// to the required drop fraction.
    private func speedDropTerm(preImpactSpeed: Double?, impactTime: Date) -> Double {
        guard let pre = preImpactSpeed, pre >= tuning.minPreImpactSpeed else { return 0 }
        guard let post = minSpeed(from: impactTime, within: tuning.stillnessWindow) else { return 0 }
        let drop = (pre - post) / pre                 // fraction of speed lost, 0...1
        guard drop > 0 else { return 0 }
        return min(1.0, drop / tuning.speedDropFraction)
    }

    /// Stillness term in `0...1`: how far the mean post-impact acceleration is
    /// below the stillness threshold. A dead-still phone scores 1; motion at or
    /// above the threshold scores 0.
    private func stillnessTerm(impactTime: Date) -> Double {
        // Ignore the impact spike itself: look at a short settle offset after it.
        let start = impactTime.addingTimeInterval(settleOffset)
        let end = impactTime.addingTimeInterval(tuning.stillnessWindow)
        let window = accelSamples.filter { $0.time >= start && $0.time <= end }
        guard !window.isEmpty else { return 0 }
        let mean = window.reduce(0.0) { $0 + $1.value } / Double(window.count)
        guard tuning.stillnessThreshold > 0 else { return 0 }
        let belowness = (tuning.stillnessThreshold - mean) / tuning.stillnessThreshold
        return min(1.0, max(0.0, belowness))
    }

    // MARK: - Helpers

    /// The newest speed at or before `time`, if any (pre-impact speed).
    private func speed(at time: Date) -> Double? {
        speedSamples.last(where: { $0.time <= time })?.value
    }

    /// The minimum speed seen in `(from, from+window]`, if any (post-impact).
    private func minSpeed(from: Date, within window: TimeInterval) -> Double? {
        let end = from.addingTimeInterval(window)
        let values = speedSamples.filter { $0.time > from && $0.time <= end }.map(\.value)
        return values.min()
    }

    private func isInCooldown(at time: Date) -> Bool {
        guard let until = cooldownUntil else { return false }
        return time < until
    }

    /// A tiny offset after the impact before measuring stillness, so the impact
    /// spike itself is excluded. One tenth of the impact window.
    private var settleOffset: TimeInterval { tuning.impactWindow * 0.1 }

    /// The longest lookback we keep samples for (the widest window plus slack).
    private var longestLookback: TimeInterval {
        max(tuning.stillnessWindow, tuning.evaluationDelay) + tuning.impactWindow + 1.0
    }

    private func trim(_ samples: inout [TimedValue], keeping lookback: TimeInterval, before now: Date) {
        let cutoff = now.addingTimeInterval(-lookback)
        samples.removeAll { $0.time < cutoff }
    }

    // MARK: - Nested value types

    /// A timestamped scalar sample.
    private struct TimedValue: Equatable {
        let time: Date
        let value: Double
    }

    /// A pending impact awaiting evaluation.
    private struct Impact: Equatable {
        let time: Date
        var peak: Double
        let preImpactSpeed: Double?
    }
}
