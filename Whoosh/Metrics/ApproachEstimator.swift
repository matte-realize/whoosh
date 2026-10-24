import Foundation

/// The pure approach heuristic that keeps a far, static vehicle from alerting
/// (rear-camera spec task (b); design "Include an approach heuristic so a far,
/// static car is not an alert"). It tracks the **largest** vehicle box's
/// smoothed normalized area over a short window and reports an approach only
/// when that area is growing fast enough, for long enough, and the box is big
/// enough.
///
/// Pure and **Foundation-only** (Metrics layer, like `NearMissPolicy`): boxes
/// are a plain normalized rect, time is a `TimeInterval`, and there is no
/// CoreVideo/`CGRect`/AVFoundation import. The caller (`VisionVehicleConsumer`)
/// maps the vision model's `VehicleBox` into `ApproachEstimator.Box` and the
/// `Approach` result into a `HazardDetection`.
///
/// This is a deliberately simpler, single-largest-box port of the multi-track
/// reference in `cv/approach.py` (which smooths box **height** across IoU-matched
/// tracks). The task framing is "largest box area growth over a window"; area
/// captures the same "getting closer" signal. All numbers live in `VisionTuning`
/// and are **hypotheses for Teammate B to tune** against `cv/approach.py` and the
/// offline evaluation (tasks B2, B3). Detection is experimental: it cannot
/// guarantee detection or delivery.
///
/// Not thread-safe by itself; the `VisionVehicleConsumer` owns one instance and
/// only ever touches it from its single detection serial queue (one frame at a
/// time), so no locking is needed. `Sendable`-free value type held by that owner.
nonisolated struct ApproachEstimator {
    /// One detected vehicle box for a frame, normalized 0...1 with a top-left
    /// origin (x right, y down) — the same convention as `VehicleBox.rect`.
    /// Framework-free so this stays in the Metrics layer.
    struct Box: Equatable {
        let label: String
        let confidence: Double
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(label: String, confidence: Double, x: Double, y: Double, width: Double, height: Double) {
            self.label = label
            self.confidence = confidence
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// Normalized area (0...1); the "getting closer" signal.
        var area: Double { max(0, width) * max(0, height) }
        /// Image-space x-center (0...1).
        var centerX: Double { x + width / 2 }
    }

    /// What the estimator reports when a vehicle is approaching. Maps directly
    /// onto `HazardDetection` by the caller.
    struct Approach: Equatable {
        /// Always `"vehicle"` for this detector (the hazard-contract `kind`).
        let kind: String
        /// The triggering box's confidence (0...1).
        let confidence: Double
        /// Coarse position **in the rider frame** ("left"/"center"/"right"); the
        /// rear image is mirrored, so image-left is the rider's right.
        let relativePositionHint: String?
    }

    private let tuning: VisionTuning

    // Single-track state for the largest box.
    private var smoothedArea: Double?
    private var lastSeen: TimeInterval?
    private var streak: Int = 0
    private var lastEmitAt: TimeInterval?
    // Sliding window of (timestamp, smoothedArea) within `growthWindow`.
    private var history: [(t: TimeInterval, area: Double)] = []

    init(tuning: VisionTuning) {
        self.tuning = tuning
    }

    /// Reset all temporal state (called on a discontinuity or when the owner
    /// restarts the pipeline).
    mutating func reset() {
        smoothedArea = nil
        lastSeen = nil
        streak = 0
        lastEmitAt = nil
        history.removeAll(keepingCapacity: true)
    }

    /// Feed one frame's vehicle boxes at `timestamp` (seconds, monotonic).
    /// Returns an `Approach` if this frame crosses the approach criteria, else
    /// `nil`. `isDiscontinuity` resets temporal state before processing.
    mutating func update(boxes: [Box], timestamp: TimeInterval, isDiscontinuity: Bool) -> Approach? {
        if isDiscontinuity { reset() }

        // Age out the track if it has not been seen within trackMaxAge.
        if let last = lastSeen, timestamp - last > tuning.trackMaxAge {
            resetTrackKeepingCooldown()
        }

        // Keep only boxes at or above the confidence floor; pick the largest.
        let candidate = boxes
            .filter { $0.confidence >= tuning.minConfidence }
            .max { $0.area < $1.area }

        guard let candidate else {
            // No vehicle this frame: the streak breaks but the track is only
            // dropped once it ages out (handled above on a later frame).
            streak = 0
            return nil
        }

        // Smooth the area (EMA). A fresh track seeds the smoothed value.
        let newSmoothed: Double
        if let previous = smoothedArea {
            let a = clamp01(tuning.emaAlpha)
            newSmoothed = a * candidate.area + (1 - a) * previous
        } else {
            newSmoothed = candidate.area
        }
        smoothedArea = newSmoothed
        lastSeen = timestamp

        // Maintain the growth window: keep the newest sample that is at least
        // `growthWindow` old at the front, so growth is measured across the span.
        history.append((t: timestamp, area: newSmoothed))
        while history.count > 2 && timestamp - history[1].t >= tuning.growthWindow {
            history.removeFirst()
        }

        // Relative growth per second over the window.
        let base = history[0]
        var growthRate = 0.0
        if timestamp > base.t, base.area > 0 {
            growthRate = (newSmoothed - base.area) / base.area / (timestamp - base.t)
        }

        // Streak of consecutive frames above the growth threshold.
        streak = growthRate > tuning.growthThresholdPerSecond ? streak + 1 : 0

        // Emit only when: streak satisfied, box big enough, and the cooldown has
        // elapsed since the last emit.
        guard streak >= tuning.consecutiveFrames,
              newSmoothed >= tuning.minSizeFraction
        else { return nil }

        if let lastEmit = lastEmitAt, timestamp - lastEmit < tuning.emitCooldown {
            return nil
        }

        lastEmitAt = timestamp
        return Approach(
            kind: "vehicle",
            confidence: candidate.confidence,
            relativePositionHint: positionHint(forImageCenterX: candidate.centerX)
        )
    }

    // MARK: - Private

    /// Drop the per-track smoothing/streak/history but keep the emit cooldown so
    /// a brief dropout cannot bypass it.
    private mutating func resetTrackKeepingCooldown() {
        smoothedArea = nil
        lastSeen = nil
        streak = 0
        history.removeAll(keepingCapacity: true)
    }

    /// Map an image-space x-center to a **rider-frame** hint. The rear camera
    /// image is mirrored relative to the rider facing forward, so image-left is
    /// rider-right and vice versa (hazard-contract decision 1).
    private func positionHint(forImageCenterX centerX: Double) -> String? {
        if centerX <= tuning.positionLeftBoundary {
            return "right"   // image-left ⇒ rider-right
        }
        if centerX >= tuning.positionRightBoundary {
            return "left"    // image-right ⇒ rider-left
        }
        return "center"
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
}
