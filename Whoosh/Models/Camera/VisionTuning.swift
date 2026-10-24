import Foundation

/// Tuning constants for the on-device vehicle detector and its approach
/// heuristic (rear-camera spec task (b); design "HazardDetector seam update").
/// Gathered in one place so nothing is hard-coded at the call sites in
/// `Services/Detection` (the `VisionVehicleConsumer` / `ApproachEstimator`).
///
/// **These defaults are hypotheses to be tuned by Teammate B** against the
/// reference pipeline in `cv/approach.py` + `cv/approach_config.json` and the
/// offline evaluation (spec tasks B2, B3). Detection auto-pinning stays off
/// until measured thresholds exist (design O-CAM6); this type only supplies the
/// heuristic's knobs. Detection is experimental — it cannot guarantee detection
/// or delivery.
///
/// Foundation-only value type (Models layer); `Equatable`, `Codable`,
/// `Sendable`. Times are `TimeInterval` (seconds), fractions are 0...1. There is
/// deliberately no `CGRect`/CoreVideo here so the Models/Metrics layering rule
/// holds (the estimator reasons over a plain, framework-free box).
///
/// ## Mapping to `cv/approach_config.json` (Teammate B's reference)
/// | This type | `approach_config.json` | Meaning |
/// | --------- | ---------------------- | ------- |
/// | `minConfidence` | `min_confidence` (0.35) | drop detections below this |
/// | `emaAlpha` | `ema_alpha` (0.4) | weight of the newest box size in the smoothed size |
/// | `growthWindow` | `growth_window_s` (0.3) | growth is measured over this span, not frame-to-frame |
/// | `growthThresholdPerSecond` | `growth_threshold_per_s` (0.3) | relative growth per second (≈ 1 / time-to-contact) |
/// | `consecutiveFrames` | `consecutive_frames` (3) | frames in a row above the growth threshold |
/// | `trackMaxAge` | `track_max_age_s` (0.5) | drop the tracked box if not seen for this long |
/// | `minSizeFraction` | `min_height_frac` (0.08) | smoothed size needed before a growth alert |
/// | `emitCooldown` | `cooldown_s` (5.0) | quiet time after an emit before the next one |
///
/// `cv/approach.py` smooths **height**; this estimator smooths normalized
/// **area** (the task framing: "largest box area growth over a window"). Area ≈
/// width × height captures the same "getting closer" signal and is slightly more
/// robust to a vehicle that is partly turned; the thresholds are re-tuned
/// accordingly by Teammate B. The default `growthThresholdPerSecond` is carried
/// over as a starting point only.
nonisolated struct VisionTuning: Equatable, Codable, Sendable {
    /// Detections below this confidence are dropped before tracking. Mirrors
    /// `VehicleDetector.minimumConfidence`'s higher near-miss bar.
    var minConfidence: Double = 0.35

    /// EMA weight for the newest box area in the smoothed area (0...1); higher
    /// reacts faster but is noisier.
    var emaAlpha: Double = 0.4

    /// The span over which relative growth is measured, so a high frame rate
    /// does not make frame-to-frame noise look like growth.
    var growthWindow: TimeInterval = 0.3

    /// Relative area growth per second that counts as "approaching" (≈ inverse
    /// time-to-contact). A far, static car grows at ~0 and never crosses this.
    var growthThresholdPerSecond: Double = 0.3

    /// How many consecutive frames must exceed the growth threshold before an
    /// event is emitted (debounces a single noisy frame).
    var consecutiveFrames: Int = 3

    /// Drop the tracked box if no box has been seen for this long (a new box
    /// then starts a fresh track with no growth history).
    var trackMaxAge: TimeInterval = 0.5

    /// The smoothed area (as a fraction of the frame) the box must reach before
    /// a growth alert — a tiny far box that doubles in size is still not close.
    var minSizeFraction: Double = 0.02

    /// Quiet time after an emit before the estimator will emit again, so one
    /// approach produces one event (the app layer applies its own cooldowns too).
    var emitCooldown: TimeInterval = 5.0

    /// Image-space x-center below this maps toward one side, above
    /// `positionRightBoundary` toward the other, in between is "center". The
    /// rear camera image is mirrored relative to the rider, so the estimator
    /// flips image-left/right to **rider-left/right** when forming the hint
    /// (hazard-contract decision 1: hints are in the rider frame).
    var positionLeftBoundary: Double = 0.4
    /// Image-space x-center at/above this maps toward the far side (see
    /// `positionLeftBoundary`).
    var positionRightBoundary: Double = 0.6

    init() {}
}
