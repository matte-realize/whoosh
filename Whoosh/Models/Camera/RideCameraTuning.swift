import Foundation

/// All rear-camera tuning constants in one place (rear-camera spec `design.md`
/// "RideCameraTuning"), so values are never hard-coded at call sites. Every
/// default is a *(verify)* hypothesis to be measured on the iPhone 14 (task 31)
/// and tuned; the ranges bound the Settings controls.
///
/// Foundation-only value type (Models layer). `Codable` so a value can be
/// persisted/serialised if needed; `Equatable` and `Sendable` so it compares in
/// tests and crosses actors. Bytes are `Int64` (sizes exceed 2 GB on 32-bit),
/// durations are `TimeInterval`, battery floors are 0...1 fractions.
///
/// Defaults (design table):
/// - Segment 15 s (range 10–30); movie-fragment 2 s; key-frame 1 s.
/// - Ring 10 min (range 2–30 min) capped at 1 GB (range 256 MB–4 GB); pinned cap 2 GB.
/// - Pin pre/post by source: manual 30/15, detection 15/10, crash 60/30; coalesce
///   gap 5 s; max clip 180 s; auto-pin cooldown 20 s; ≤ 10 auto-pins/ride; manual
///   save debounce 2 s.
/// - Free space start 2 GB / warn 1 GB / stop 500 MB.
/// - Battery: suggest Efficient ≤ 20%, stop ≤ 8% unplugged.
/// - Interrupted notice after 5 s; 3 resume attempts within 30 s.
/// - Mount grace 20 s (range 5–60); two-finger 1.0 s unlock hold; 10 s unlock
///   inactivity window; dim to 0.0; red-dot shift every 60 s.
/// - Clip retention 30 days (O-CAM4); 10 s test recording.
/// - Background finalize budget ≤ 3 s; writer restart after 2 s.
struct RideCameraTuning: Equatable, Codable, Sendable {
    // Segments
    var segmentLength: TimeInterval = 15
    var movieFragmentInterval: TimeInterval = 2
    var keyFrameInterval: TimeInterval = 1

    // Ring buffer
    var ringMaxDuration: TimeInterval = 10 * 60
    var ringMaxBytes: Int64 = 1_000_000_000
    var pinnedMaxBytes: Int64 = 2_000_000_000

    // Pin windows (pre/post seconds by source)
    var manualPinPre: TimeInterval = 30
    var manualPinPost: TimeInterval = 15
    var detectionPinPre: TimeInterval = 15
    var detectionPinPost: TimeInterval = 10
    var crashPinPre: TimeInterval = 60
    var crashPinPost: TimeInterval = 30

    // Coalescing and auto-pin caps
    var coalesceGap: TimeInterval = 5
    var maxClipDuration: TimeInterval = 180
    var autoPinCooldown: TimeInterval = 20
    var maxAutoPinsPerRide: Int = 10
    var manualSaveDebounce: TimeInterval = 2

    // Storage guard (bytes)
    var freeSpaceStart: Int64 = 2_000_000_000
    var freeSpaceWarn: Int64 = 1_000_000_000
    var freeSpaceStop: Int64 = 500_000_000

    // Battery floors (0...1 fractions)
    var batterySuggestEfficient: Double = 0.20
    var batteryStopFloor: Double = 0.08

    // Interruption / resume
    var interruptedNoticeThreshold: TimeInterval = 5
    var resumeAttempts: Int = 3
    var resumeAttemptWindow: TimeInterval = 30

    // Ride mode / screen
    var mountGrace: TimeInterval = 20
    var unlockHoldDuration: TimeInterval = 1.0
    var unlockInactivityWindow: TimeInterval = 10
    var dimBrightness: Double = 0.0
    var redDotShiftPeriod: TimeInterval = 60

    // Alert routing cooldowns (design "Eyes-free surfaces": rear-vehicle caution
    // at most once per 3 s; camera notices at most once per minute per reason).
    var rearVehicleAlertCooldown: TimeInterval = 3
    var cameraNoticeCooldown: TimeInterval = 60

    // Eyes-free status heartbeat (design: publish on change plus a 5 s heartbeat).
    var statusHeartbeat: TimeInterval = 5

    // Retention / misc
    var clipRetention: TimeInterval = 30 * 24 * 60 * 60
    var testRecordingLength: TimeInterval = 10
    var backgroundFinalizeBudget: TimeInterval = 3
    var writerRestartDelay: TimeInterval = 2

    init() {}

    // MARK: - Ranges (bound the Settings controls)

    /// Segment length range (design: 10–30 s).
    var segmentLengthRange: ClosedRange<TimeInterval> { 10...30 }
    /// Ring duration range (design: 2–30 min, Settings "Buffer length").
    var ringMaxDurationRange: ClosedRange<TimeInterval> { (2 * 60)...(30 * 60) }
    /// Ring byte cap range (design: 256 MB–4 GB).
    var ringMaxBytesRange: ClosedRange<Int64> { 256_000_000...4_000_000_000 }
    /// Mount-grace range (design: 5–60 s).
    var mountGraceRange: ClosedRange<TimeInterval> { 5...60 }

    // MARK: - Clamps

    /// Clamp a requested segment length into the allowed range.
    func clampSegmentLength(_ requested: TimeInterval) -> TimeInterval {
        clamp(requested, to: segmentLengthRange)
    }

    /// Clamp a requested ring duration into the allowed range.
    func clampRingMaxDuration(_ requested: TimeInterval) -> TimeInterval {
        clamp(requested, to: ringMaxDurationRange)
    }

    /// Clamp a requested ring byte cap into the allowed range.
    func clampRingMaxBytes(_ requested: Int64) -> Int64 {
        clamp(requested, to: ringMaxBytesRange)
    }

    /// Clamp a requested mount-grace length into the allowed range.
    func clampMountGrace(_ requested: TimeInterval) -> TimeInterval {
        clamp(requested, to: mountGraceRange)
    }

    // MARK: - Pin windows

    /// The (pre, post) pin window lengths in seconds for a clip source. `demo`
    /// mirrors the manual window (demo-mode uses the same pinning path).
    func pinPrePost(for reason: ClipReason) -> (pre: TimeInterval, post: TimeInterval) {
        switch reason {
        case .manual, .demo:
            return (manualPinPre, manualPinPost)
        case .detection:
            return (detectionPinPre, detectionPinPost)
        case .crash:
            return (crashPinPre, crashPinPost)
        }
    }

    // MARK: - Private

    private func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
