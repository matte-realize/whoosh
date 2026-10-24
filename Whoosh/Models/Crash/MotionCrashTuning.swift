import Foundation

/// Tuning constants for the **experimental** motion-based crash signal core
/// (crash-response task 32, Requirement 5.5/5.6/19.7). Kept separate from
/// `CrashResponseTuning` (which tunes the alert/countdown pipeline) so the
/// detector's thresholds live in one place and can be measured and adjusted
/// without touching the alert flow — the spec allows either type, and a
/// dedicated `MotionCrashTuning` keeps the alert tuning uncluttered.
///
/// Foundation-only value type (Models layer). `Equatable`, `Codable`, `Sendable`
/// so it compares in tests and crosses actors. **Every threshold the signal core
/// uses lives here**; the core never hard-codes a number.
///
/// ## The heuristic, in one paragraph
/// A probable crash looks like a **short, large acceleration spike** (the impact)
/// followed by the rider going **much slower** (a GPS speed drop) and the phone
/// becoming **unusually still** (the rider is down, not pedaling). None of the
/// three alone is a crash — a pothole spikes acceleration but speed and motion
/// continue; a hard stop drops speed but has no violent spike; setting the phone
/// down is still but had no impact or speed. The core requires an impact **and**
/// corroborating evidence, then scores `0...1`. The countdown with its large
/// "I'm OK — Cancel" is the false-positive safety net (design O9); this detector
/// is deliberately conservative and labeled experimental.
///
/// ## Documented defaults (all units SI, matching the app's internal storage)
/// - `impactThresholdG` = **4.0 g** — user acceleration magnitude (gravity
///   removed) that counts as an impact. Normal cycling, potholes, and curb
///   bumps on a mounted phone rarely exceed ~2–3 g for a sustained reading; a
///   bike crash commonly shows a brief spike well above this. Conservative on
///   purpose.
/// - `impactWindow` = **1.0 s** — the impact must appear within this trailing
///   window to still be "recent" when corroboration is evaluated.
/// - `speedDropFraction` = **0.6** — require speed to fall to ≤ 40% of the
///   pre-impact speed (a 60% drop) shortly after the impact.
/// - `minPreImpactSpeed` = **3.0 m/s** (~6.7 mph) — below this the rider was
///   barely moving, so a "speed drop" is meaningless; require real riding speed
///   before the impact to consider a crash.
/// - `stillnessWindow` = **2.5 s** — how long after the impact to watch for
///   unusual stillness.
/// - `stillnessThresholdG` = **0.15 g** — mean user-acceleration magnitude in the
///   stillness window at or below this reads as "the phone/rider went still".
/// - `evaluationDelay` = **2.5 s** — wait this long after an impact before
///   scoring, so the speed-drop and stillness windows have data (equals
///   `stillnessWindow`).
/// - `triggerScore` = **0.7** — minimum combined score `0...1` to emit a signal.
/// - Score weights (sum ≈ 1.0): `impactWeight` 0.4, `speedDropWeight` 0.35,
///   `stillnessWeight` 0.25. The impact is necessary (gating), the other two
///   corroborate.
/// - `cooldown` = **8.0 s** — after any evaluation, ignore new impacts for this
///   long so one event does not score repeatedly (the coordinator also
///   suppresses, but the core is cheap to gate).
struct MotionCrashTuning: Equatable, Codable, Sendable {
    /// Standard gravity in m/s², used to express acceleration thresholds in g.
    static let gravity: Double = 9.80665

    /// User-acceleration magnitude (gravity removed) that counts as an impact, in g.
    var impactThresholdG: Double = 4.0
    /// Trailing window in which an impact is still "recent" for corroboration, seconds.
    var impactWindow: TimeInterval = 1.0
    /// Require speed to fall by at least this fraction of pre-impact speed (0...1).
    var speedDropFraction: Double = 0.6
    /// Minimum pre-impact speed for a speed drop to be meaningful, m/s.
    var minPreImpactSpeed: Double = 3.0
    /// Window after the impact watched for unusual stillness, seconds.
    var stillnessWindow: TimeInterval = 2.5
    /// Mean user-acceleration magnitude at/below which the window reads as still, g.
    var stillnessThresholdG: Double = 0.15
    /// Delay after an impact before scoring, so corroboration windows have data, seconds.
    var evaluationDelay: TimeInterval = 2.5
    /// Minimum combined score (0...1) required to emit a probable-crash signal.
    var triggerScore: Double = 0.7
    /// Weight of the (gating) impact term in the combined score.
    var impactWeight: Double = 0.4
    /// Weight of the GPS speed-drop term.
    var speedDropWeight: Double = 0.35
    /// Weight of the post-impact stillness term.
    var stillnessWeight: Double = 0.25
    /// After an evaluation, ignore new impacts for this long, seconds.
    var cooldown: TimeInterval = 8.0

    init(
        impactThresholdG: Double = 4.0,
        impactWindow: TimeInterval = 1.0,
        speedDropFraction: Double = 0.6,
        minPreImpactSpeed: Double = 3.0,
        stillnessWindow: TimeInterval = 2.5,
        stillnessThresholdG: Double = 0.15,
        evaluationDelay: TimeInterval = 2.5,
        triggerScore: Double = 0.7,
        impactWeight: Double = 0.4,
        speedDropWeight: Double = 0.35,
        stillnessWeight: Double = 0.25,
        cooldown: TimeInterval = 8.0
    ) {
        self.impactThresholdG = impactThresholdG
        self.impactWindow = impactWindow
        self.speedDropFraction = speedDropFraction
        self.minPreImpactSpeed = minPreImpactSpeed
        self.stillnessWindow = stillnessWindow
        self.stillnessThresholdG = stillnessThresholdG
        self.evaluationDelay = evaluationDelay
        self.triggerScore = triggerScore
        self.impactWeight = impactWeight
        self.speedDropWeight = speedDropWeight
        self.stillnessWeight = stillnessWeight
        self.cooldown = cooldown
    }

    /// The impact threshold expressed in m/s² (the unit of a user-acceleration sample).
    var impactThreshold: Double { impactThresholdG * Self.gravity }

    /// The stillness threshold expressed in m/s².
    var stillnessThreshold: Double { stillnessThresholdG * Self.gravity }
}
