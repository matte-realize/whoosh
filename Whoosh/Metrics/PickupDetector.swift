import Foundation

/// A pure, Foundation-only heuristic that decides when the phone has been
/// **picked up** from its mount, from the gravity vector the mount sensor
/// already streams (owner device-testing feedback: "detect the phone being
/// picked up … a large attitude/orientation change or sustained motion … and
/// respond by temporarily raising brightness and showing the unlock prompt").
///
/// It does this without Core Motion: `GravityVector` is the normalized gravity
/// direction in the device frame, so the **angle** between a settled reference
/// direction and the current one is exactly the attitude change. When that angle
/// exceeds `thresholdRadians` the phone has been tilted/lifted enough to count as
/// a pickup. A short debounce (`minInterval`) keeps a single lift from firing
/// repeatedly, and the reference re-settles once motion calms so a new resting
/// pose becomes the baseline.
///
/// Pure value type (Metrics layer, like `ApproachEstimator` / `LevelCalculator`):
/// no Core Motion, no clock reads — the caller passes the sample's timestamp.
/// The owner (`RideModeController`) holds one instance and only touches it on the
/// main actor, so no locking is needed. Detection here is a convenience cue, not
/// a safety guarantee.
struct PickupDetector {
    /// Attitude-change angle (radians) that counts as a pickup. ~0.5 rad ≈ 29°,
    /// well beyond mount jitter but easily reached by lifting the phone.
    let thresholdRadians: Double
    /// Minimum seconds between two reported pickups (debounce).
    let minInterval: TimeInterval
    /// Per-sample change (radians) below which the pose is considered "steady",
    /// so the reference re-baselines to the current resting pose. Lets a later
    /// lift from a new resting pose be detected too.
    let settleRadians: Double

    /// The settled reference gravity direction; `nil` until the first sample.
    private var reference: GravityVector?
    /// The previous sample, to measure per-sample change (steadiness).
    private var previous: GravityVector?
    /// The last instant a pickup was reported (debounce).
    private var lastFiredAt: TimeInterval?

    init(
        thresholdRadians: Double = 0.5,
        minInterval: TimeInterval = 3,
        settleRadians: Double = 0.15
    ) {
        self.thresholdRadians = thresholdRadians
        self.minInterval = minInterval
        self.settleRadians = settleRadians
    }

    /// Reset all state (e.g. when the mount sensor restarts or ride mode
    /// re-arms). The next sample becomes the new reference.
    mutating func reset() {
        reference = nil
        previous = nil
        lastFiredAt = nil
    }

    /// Feed one gravity sample at `timestamp` (seconds, monotonic). Returns
    /// `true` exactly once when the attitude change from the settled reference
    /// first crosses the threshold (subject to the debounce). The reference
    /// re-baselines whenever the pose is steady (small per-sample change), so a
    /// later lift from a new resting pose is detected too.
    mutating func update(gravity: GravityVector, timestamp: TimeInterval) -> Bool {
        defer { previous = gravity }

        guard let reference else {
            self.reference = gravity
            return false
        }

        // If the pose is steady (little change from the previous sample), treat
        // the current direction as the new resting reference and don't fire.
        if let previous, Self.angleBetween(previous, gravity) <= settleRadians {
            // Only rebaseline toward a steady pose; keep the debounce intact.
            self.reference = gravity
        }

        let angle = Self.angleBetween(self.reference ?? reference, gravity)
        guard angle >= thresholdRadians else { return false }

        // Debounce: don't re-fire within minInterval of the last pickup.
        if let lastFiredAt, timestamp - lastFiredAt < minInterval {
            return false
        }

        lastFiredAt = timestamp
        return true
    }

    // MARK: - Pure geometry

    /// The angle (radians, `0...π`) between two gravity direction vectors. Robust
    /// to non-unit inputs (normalizes); returns 0 for a degenerate zero vector.
    static func angleBetween(_ a: GravityVector, _ b: GravityVector) -> Double {
        let magA = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        let magB = (b.x * b.x + b.y * b.y + b.z * b.z).squareRoot()
        guard magA > 0, magB > 0 else { return 0 }
        let dot = a.x * b.x + a.y * b.y + a.z * b.z
        let cosine = min(1, max(-1, dot / (magA * magB)))
        return Foundation.acos(cosine)
    }
}
