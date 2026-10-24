import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `FrameDropPolicy` (rear-camera spec task 6,
/// Requirements 4.4, 4.5, 4.8; design "FrameDropPolicy" table). Written
/// test-first from the design's eight-row table, one `@Test` per row.
///
/// The policy decides, per consumer, whether a newly offered frame should be
/// delivered or rate-dropped, given the frame's presentation time, the time of
/// the consumer's last *delivered* frame, and the consumer's declared maximum
/// frames per second. It also reports a discontinuity across a large gap so a
/// detector can reset temporal state, and resets its baseline when the clock
/// jumps backward. It is a pure function over `TimeInterval` seconds — no
/// AVFoundation, no `CMTime`, no `Clock` needed (the presentation time is the
/// input).
struct FrameDropPolicyTests {
    // Standard capture rate used by several rows.
    private let captureFps: Double = 30

    // MARK: FD-1 — first frame for a consumer always passes

    @Test func fd1_firstFramePasses() {
        let decision = FrameDropPolicy.decide(
            frameTime: 0,
            lastDeliveredTime: nil,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
        #expect(decision.isDiscontinuity == false)
    }

    // MARK: FD-2 — on-rate (Δt ≥ 0.9 × interval) passes

    @Test func fd2_onRatePasses() {
        // maxFPS = 10 ⇒ interval 0.1 s ⇒ jitter threshold 0.09 s.
        let decision = FrameDropPolicy.decide(
            frameTime: 0.10,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
        #expect(decision.isDiscontinuity == false)
    }

    @Test func fd2b_exactlyAtJitterTolerancePasses() {
        // Δt == 0.9 × interval (0.09 s) is still "on-rate" (inclusive).
        let decision = FrameDropPolicy.decide(
            frameTime: 0.09,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
    }

    // MARK: FD-3 — too soon (Δt < 0.9 × interval) drops (rate)

    @Test func fd3_tooSoonDropsRate() {
        // Δt = 0.05 s < 0.09 s jitter threshold.
        let decision = FrameDropPolicy.decide(
            frameTime: 0.05,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver == false)
        #expect(decision.reason == .rate)
    }

    // MARK: FD-4 — clock jump backward passes and resets the baseline

    @Test func fd4_backwardClockPassesAndResets() {
        // A frame whose time is before the last delivered time (session reset,
        // clock jump): deliver and treat as a fresh baseline.
        let decision = FrameDropPolicy.decide(
            frameTime: 5.0,
            lastDeliveredTime: 10.0,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
        #expect(decision.resetBaseline)
    }

    // MARK: FD-5 — large gap (Δt > 1 s) passes and flags a discontinuity

    @Test func fd5_largeGapPassesWithDiscontinuity() {
        let decision = FrameDropPolicy.decide(
            frameTime: 2.0,
            lastDeliveredTime: 0.5,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
        #expect(decision.isDiscontinuity)
    }

    @Test func fd5b_gapExactlyOneSecondIsNotYetDiscontinuity() {
        // Boundary: Δt == 1 s is on-rate (well above interval) but not a gap.
        let decision = FrameDropPolicy.decide(
            frameTime: 1.0,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 10
        )
        #expect(decision.shouldDeliver)
        #expect(decision.isDiscontinuity == false)
    }

    // MARK: FD-6 — maxFPS ≥ capture fps passes every frame

    @Test func fd6_maxFpsAtOrAboveCapturePassesEveryFrame() {
        // maxFPS 30 ⇒ interval 1/30 s; a frame one capture-interval later passes.
        let dt = 1.0 / captureFps
        let decision = FrameDropPolicy.decide(
            frameTime: dt,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 30
        )
        #expect(decision.shouldDeliver)
    }

    @Test func fd6b_maxFpsAboveCapturePassesEveryFrame() {
        let dt = 1.0 / captureFps
        let decision = FrameDropPolicy.decide(
            frameTime: dt,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 120
        )
        #expect(decision.shouldDeliver)
    }

    // MARK: FD-7 — maxFPS = 0 or invalid clamps to 1 fps

    @Test func fd7_zeroMaxFpsClampsToOneFps() {
        // Clamped to 1 fps ⇒ interval 1 s ⇒ jitter threshold 0.9 s.
        // A frame 0.5 s later is too soon.
        let tooSoon = FrameDropPolicy.decide(
            frameTime: 0.5,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 0
        )
        #expect(tooSoon.shouldDeliver == false)
        #expect(tooSoon.reason == .rate)

        // A frame 0.95 s later passes (≥ 0.9 s).
        let onRate = FrameDropPolicy.decide(
            frameTime: 0.95,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: 0
        )
        #expect(onRate.shouldDeliver)
    }

    @Test func fd7b_negativeMaxFpsClampsToOneFps() {
        let decision = FrameDropPolicy.decide(
            frameTime: 0.5,
            lastDeliveredTime: 0.0,
            maxFramesPerSecond: -5
        )
        #expect(decision.shouldDeliver == false)
        #expect(decision.reason == .rate)
    }

    // MARK: FD-8 — capture rate ≤ max: a steady capture stream is never rate-dropped

    @Test func fd8_captureRateAtMostMaxNeverRateDrops() {
        // Capture at 10 fps, consumer maxFPS 10: every captured frame should pass.
        let interval = 1.0 / 10.0
        var last: TimeInterval? = nil
        var delivered = 0
        for i in 0..<20 {
            let t = Double(i) * interval
            let decision = FrameDropPolicy.decide(
                frameTime: t,
                lastDeliveredTime: last,
                maxFramesPerSecond: 10
            )
            if decision.shouldDeliver {
                delivered += 1
                last = t
            }
        }
        #expect(delivered == 20)
    }

    // MARK: Oversupply — capture faster than max is down-sampled

    @Test func oversupplyIsDownSampledTowardMax() {
        // Capture at 30 fps, consumer maxFPS 10: roughly a third pass.
        let captureInterval = 1.0 / 30.0
        var last: TimeInterval? = nil
        var delivered = 0
        for i in 0..<90 { // 3 seconds of 30 fps
            let t = Double(i) * captureInterval
            let decision = FrameDropPolicy.decide(
                frameTime: t,
                lastDeliveredTime: last,
                maxFramesPerSecond: 10
            )
            if decision.shouldDeliver {
                delivered += 1
                last = t
            }
        }
        // ~10 fps over 3 s ≈ 30 frames; allow a small boundary tolerance.
        #expect(delivered >= 28)
        #expect(delivered <= 31)
    }
}
