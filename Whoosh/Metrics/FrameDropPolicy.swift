import Foundation

/// Pure per-consumer frame rate-limiting policy (rear-camera spec task 6,
/// Requirements 4.4, 4.5, 4.8; design "FrameDropPolicy" table). Pure,
/// framework-free (Metrics layer): it reasons over `TimeInterval` seconds only —
/// no AVFoundation, no `CMTime`, no `CVPixelBuffer`. The `FramePipeline`
/// (task 11) calls it *before* a consumer's single-slot mailbox so frames above
/// the consumer's declared maximum rate are dropped cheaply and never queue.
///
/// Inputs per decision:
/// - `frameTime`: the offered frame's monotonic presentation time (seconds).
/// - `lastDeliveredTime`: the presentation time of the consumer's last
///   *delivered* frame, or `nil` if none has been delivered yet.
/// - `maxFramesPerSecond`: the consumer's declared cap (clamped to ≥ 1).
///
/// The design's table (one `@Test` per row in `FrameDropPolicyTests`):
///
/// | Case | Inputs | Output |
/// | ---- | ------ | ------ |
/// | First frame | no last delivered | pass |
/// | On-rate | Δt ≥ 0.9 × (1 / maxFPS) | pass |
/// | Too soon | Δt < 0.9 × interval | drop(rate) |
/// | Clock jump backward | Δt < 0 | pass, reset baseline |
/// | Large gap | Δt > 1 s | pass, flag discontinuity |
/// | Consumer busy | pending occupied | (handled by the mailbox, not here) |
/// | maxFPS ≥ capture fps | — | pass every frame |
/// | maxFPS = 0 or invalid | — | clamp to 1 fps |
///
/// The "consumer busy" row is a mailbox concern (latest-wins), handled by
/// `FramePipeline`, not by this rate policy.
nonisolated enum FrameDropPolicy {
    /// Jitter tolerance: a frame arriving at ≥ 90% of the nominal interval is
    /// still considered on-rate (design backpressure rule 4). Exposed so the
    /// pipeline and tests share one value.
    static let jitterTolerance: Double = 0.9

    /// A gap larger than this (seconds) is treated as a discontinuity so a
    /// consumer can reset temporal state (design row "Large gap", Req 4.8).
    static let discontinuityGap: TimeInterval = 1.0

    /// Why a frame was dropped (only `rate` for this pure policy; busy-drops are
    /// counted by the pipeline's mailbox).
    enum DropReason: Equatable, Sendable {
        case rate
    }

    /// The outcome of a single decision.
    struct Decision: Equatable, Sendable {
        /// Whether the pipeline should deliver this frame to the consumer.
        let shouldDeliver: Bool
        /// When not delivering, why. `nil` when `shouldDeliver` is true.
        let reason: DropReason?
        /// Whether the consumer should treat this frame as a discontinuity
        /// (reset temporal state). Only set on delivered frames across a large
        /// gap or a backward clock jump.
        let isDiscontinuity: Bool
        /// Whether the policy reset its rate baseline for this consumer (a
        /// backward clock jump). The pipeline simply uses `frameTime` as the new
        /// last-delivered time, which it already does on any delivery; this flag
        /// is diagnostic.
        let resetBaseline: Bool

        fileprivate static func deliver(
            discontinuity: Bool = false,
            resetBaseline: Bool = false
        ) -> Decision {
            Decision(
                shouldDeliver: true,
                reason: nil,
                isDiscontinuity: discontinuity,
                resetBaseline: resetBaseline
            )
        }

        fileprivate static func drop(_ reason: DropReason) -> Decision {
            Decision(
                shouldDeliver: false,
                reason: reason,
                isDiscontinuity: false,
                resetBaseline: false
            )
        }
    }

    /// Decide whether to deliver `frameTime` to a consumer whose last delivered
    /// frame was at `lastDeliveredTime`, given its `maxFramesPerSecond`.
    ///
    /// Pure and total: every input combination returns a `Decision`.
    static func decide(
        frameTime: TimeInterval,
        lastDeliveredTime: TimeInterval?,
        maxFramesPerSecond: Double
    ) -> Decision {
        // First frame for a consumer always passes (nothing to rate-limit
        // against). It is not a discontinuity by itself; the pipeline flags a
        // freshly registered consumer's first frame separately.
        guard let last = lastDeliveredTime else {
            return .deliver()
        }

        let delta = frameTime - last

        // Clock jump backward: a session reset or out-of-order input. Pass and
        // reset the baseline so the next interval is measured from here.
        if delta < 0 {
            return .deliver(resetBaseline: true)
        }

        // Large gap: an interruption/restart/format change. Pass and flag a
        // discontinuity so a detector resets temporal state.
        if delta > discontinuityGap {
            return .deliver(discontinuity: true)
        }

        // Rate limit with jitter tolerance. Clamp an invalid cap to 1 fps.
        let clampedFps = maxFramesPerSecond.isFinite && maxFramesPerSecond >= 1
            ? maxFramesPerSecond
            : 1.0
        let interval = 1.0 / clampedFps
        let threshold = jitterTolerance * interval

        // Inclusive boundary; the epsilon absorbs floating-point error
        // (0.9 × 0.1 is 0.09000000000000001, which would drop a frame at 0.09).
        if delta >= threshold - 1e-9 {
            return .deliver()
        }
        return .drop(.rate)
    }
}
