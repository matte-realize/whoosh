import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `ApproachEstimator` (rear-camera spec task (b); the
/// approach heuristic that keeps a far, static car from alerting). Written
/// test-first on synthetic box sequences.
///
/// The estimator tracks the **largest** vehicle box's smoothed area over a short
/// window and only reports an approach when the relative area growth per second
/// exceeds `growthThresholdPerSecond` for `consecutiveFrames` frames, the box is
/// at least `minSizeFraction` of the frame, and the per-track `emitCooldown` has
/// elapsed. It is pure and Foundation-only (Metrics layer): boxes are a plain
/// normalized rect, time is a `TimeInterval`, no CoreVideo/CGRect.
///
/// The thresholds come from `VisionTuning` (defaults mapped from
/// `cv/approach_config.json`); these tests drive the estimator with a tuning
/// value so they do not depend on the exact production defaults beyond the
/// documented behavior.
struct ApproachEstimatorTests {
    private func tuning(
        growthThreshold: Double = 0.3,
        consecutive: Int = 3,
        window: TimeInterval = 0.3,
        minSize: Double = 0.01,
        minConfidence: Double = 0.35,
        emaAlpha: Double = 1.0,
        cooldown: TimeInterval = 5,
        trackMaxAge: TimeInterval = 0.5
    ) -> VisionTuning {
        var t = VisionTuning()
        t.growthThresholdPerSecond = growthThreshold
        t.consecutiveFrames = consecutive
        t.growthWindow = window
        t.minSizeFraction = minSize
        t.minConfidence = minConfidence
        t.emaAlpha = emaAlpha
        t.emitCooldown = cooldown
        t.trackMaxAge = trackMaxAge
        return t
    }

    /// A centered square box with the given side length (normalized), top-left origin.
    private func box(side: Double, confidence: Double = 0.9, label: String = "car") -> ApproachEstimator.Box {
        let origin = (1.0 - side) / 2.0
        return ApproachEstimator.Box(
            label: label,
            confidence: confidence,
            x: origin, y: origin, width: side, height: side
        )
    }

    // AE-1: a far, static car (constant small box) never emits.
    @Test func staticCarNeverEmits() {
        var est = ApproachEstimator(tuning: tuning())
        var emitted = false
        for i in 0..<30 {
            let t = Double(i) * 0.1
            if est.update(boxes: [box(side: 0.1)], timestamp: t, isDiscontinuity: false) != nil {
                emitted = true
            }
        }
        #expect(emitted == false)
    }

    // AE-2: an approaching car (box area growing fast) emits after the
    // consecutive-frame streak is satisfied.
    @Test func approachingCarEmits() {
        var est = ApproachEstimator(tuning: tuning(emaAlpha: 1.0))
        var firstEmit: ApproachEstimator.Approach?
        // Grow the side ~12% per 0.1 s step ⇒ area grows ~25%/step ⇒ ~2.5 /s,
        // well above the 0.3 /s threshold.
        var side = 0.1
        for i in 0..<10 {
            let t = Double(i) * 0.1
            let result = est.update(boxes: [box(side: side)], timestamp: t, isDiscontinuity: false)
            if firstEmit == nil { firstEmit = result }
            side *= 1.12
        }
        #expect(firstEmit != nil)
        #expect(firstEmit?.kind == "vehicle")
    }

    // AE-3: growth above threshold but for fewer than `consecutiveFrames` frames
    // does not emit.
    @Test func shortGrowthDoesNotEmit() {
        var est = ApproachEstimator(tuning: tuning(consecutive: 5, emaAlpha: 1.0))
        var emitted = false
        var side = 0.1
        // Only 3 growing frames, then stop (consecutive requirement is 5).
        for i in 0..<4 {
            let t = Double(i) * 0.1
            if est.update(boxes: [box(side: side)], timestamp: t, isDiscontinuity: false) != nil {
                emitted = true
            }
            side *= 1.12
        }
        #expect(emitted == false)
    }

    // AE-4: a box below `minSizeFraction` never emits even while growing (a tiny
    // far box that doubles is still far).
    @Test func tooSmallNeverEmits() {
        var est = ApproachEstimator(tuning: tuning(minSize: 0.2, emaAlpha: 1.0))
        var emitted = false
        var side = 0.01
        for i in 0..<10 {
            let t = Double(i) * 0.1
            if est.update(boxes: [box(side: side)], timestamp: t, isDiscontinuity: false) != nil {
                emitted = true
            }
            side *= 1.12   // stays well under sqrt(0.2) ≈ 0.447 side
        }
        #expect(emitted == false)
    }

    // AE-5: detections below the confidence floor are dropped before tracking,
    // so they cannot drive an approach.
    @Test func lowConfidenceDropped() {
        var est = ApproachEstimator(tuning: tuning(minConfidence: 0.5, emaAlpha: 1.0))
        var emitted = false
        var side = 0.1
        for i in 0..<10 {
            let t = Double(i) * 0.1
            if est.update(boxes: [box(side: side, confidence: 0.4)], timestamp: t, isDiscontinuity: false) != nil {
                emitted = true
            }
            side *= 1.12
        }
        #expect(emitted == false)
    }

    // AE-6: the estimator tracks the LARGEST box when several are present, so a
    // large approaching vehicle drives the decision even with small static ones.
    @Test func tracksLargestBox() {
        var est = ApproachEstimator(tuning: tuning(emaAlpha: 1.0))
        var firstEmit: ApproachEstimator.Approach?
        var side = 0.2
        for i in 0..<10 {
            let t = Double(i) * 0.1
            let small = box(side: 0.05)     // static, small
            let big = box(side: side)       // growing, large
            let result = est.update(boxes: [small, big], timestamp: t, isDiscontinuity: false)
            if firstEmit == nil { firstEmit = result }
            side *= 1.12
        }
        #expect(firstEmit != nil)
    }

    // AE-7: a discontinuity resets temporal state, so growth history does not
    // leak across an interruption/restart.
    @Test func discontinuityResets() {
        var est = ApproachEstimator(tuning: tuning(consecutive: 3, emaAlpha: 1.0))
        var side = 0.1
        // Build up 2 growing frames (not yet enough for the streak of 3).
        for i in 0..<2 {
            _ = est.update(boxes: [box(side: side)], timestamp: Double(i) * 0.1, isDiscontinuity: false)
            side *= 1.12
        }
        // Next frame is a discontinuity: the streak must restart from here.
        var emitted = false
        // First post-discontinuity frame (streak resets, baseline reset).
        if est.update(boxes: [box(side: side)], timestamp: 0.2, isDiscontinuity: true) != nil { emitted = true }
        side *= 1.12
        // Two more growing frames: streak is only 2 again, still no emit.
        for i in 3..<5 {
            if est.update(boxes: [box(side: side)], timestamp: Double(i) * 0.1, isDiscontinuity: false) != nil {
                emitted = true
            }
            side *= 1.12
        }
        #expect(emitted == false)
    }

    // AE-8: after an emit, the cooldown suppresses further emits until it elapses.
    @Test func emitCooldownSuppresses() {
        var est = ApproachEstimator(tuning: tuning(consecutive: 3, emaAlpha: 1.0, cooldown: 5))
        var emits = 0
        var side = 0.1
        // Keep a vehicle approaching for a long time; without cooldown this would
        // emit many times. With a 5 s cooldown over ~2 s it emits at most once.
        for i in 0..<20 {
            let t = Double(i) * 0.1
            if est.update(boxes: [box(side: side)], timestamp: t, isDiscontinuity: false) != nil {
                emits += 1
            }
            side = min(side * 1.12, 0.9)
        }
        #expect(emits == 1)
    }

    // AE-9: position hint is in the RIDER frame (image is mirrored). A box on the
    // image's right (x-center > right boundary) is on the rider's LEFT.
    @Test func positionHintIsRiderFrame() {
        var t = tuning(emaAlpha: 1.0)
        t.positionLeftBoundary = 0.4
        t.positionRightBoundary = 0.6
        var est = ApproachEstimator(tuning: t)
        var emit: ApproachEstimator.Approach?
        // A growing box sitting on the right side of the IMAGE (x from 0.7).
        var side = 0.1
        for i in 0..<10 {
            let ts = Double(i) * 0.1
            let b = ApproachEstimator.Box(label: "car", confidence: 0.9,
                                          x: 0.75, y: 0.4, width: side, height: side)
            let result = est.update(boxes: [b], timestamp: ts, isDiscontinuity: false)
            if emit == nil { emit = result }
            side *= 1.12
        }
        #expect(emit != nil)
        // Image-right ⇒ rider-left.
        #expect(emit?.relativePositionHint == "left")
    }

    // AE-10: an empty frame mid-approach past trackMaxAge drops the track, so the
    // next box starts fresh with no inherited growth.
    @Test func trackAgesOut() {
        var est = ApproachEstimator(tuning: tuning(consecutive: 3, emaAlpha: 1.0, trackMaxAge: 0.2))
        var side = 0.1
        for i in 0..<2 {
            _ = est.update(boxes: [box(side: side)], timestamp: Double(i) * 0.1, isDiscontinuity: false)
            side *= 1.12
        }
        // A long gap with no boxes (> trackMaxAge).
        _ = est.update(boxes: [], timestamp: 1.0, isDiscontinuity: false)
        _ = est.update(boxes: [], timestamp: 1.5, isDiscontinuity: false)
        // Resume growth: the streak must have restarted, so 2 frames is not enough.
        var emitted = false
        for i in 0..<2 {
            if est.update(boxes: [box(side: side)], timestamp: 2.0 + Double(i) * 0.1, isDiscontinuity: false) != nil {
                emitted = true
            }
            side *= 1.12
        }
        #expect(emitted == false)
    }
}
