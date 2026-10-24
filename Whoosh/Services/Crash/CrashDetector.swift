import Foundation

/// A probable-crash signal emitted by a `CrashDetector` (spec Requirement 5.1,
/// design "Service protocols"). Carries the detection instant, a `0...1`
/// confidence score, a short human-readable `source` label, and whether this is
/// a drill (the "Simulate crash" demo path, which uses the `drill` template and
/// does not consume the per-ride cap).
///
/// Foundation-only value type; `Equatable`, `Sendable` so it can cross the
/// actor boundary from a background detector to the main-actor coordinator.
struct CrashSignal: Equatable, Sendable {
    /// When the probable crash was detected (the detector's clock).
    let timestamp: Date
    /// Detector confidence in `0...1`. A debug simulator emits `1.0`.
    let confidence: Double
    /// A short source label for the record, e.g. `"simulator"` or `"motion"`.
    let source: String
    /// `true` for the demo/drill path; `false` for a real detection.
    let isDrill: Bool

    init(timestamp: Date, confidence: Double, source: String, isDrill: Bool) {
        self.timestamp = timestamp
        self.confidence = confidence
        self.source = source
        self.isDrill = isDrill
    }
}

/// Abstracts probable-crash detection so the coordinator is driven by a signal
/// it can fake in tests (spec Requirement 5.1, 5.7, 5.8). Concrete detectors are
/// a `NoopCrashDetector`, a `FakeCrashDetector` (tests/previews), a
/// `DebugCrashSimulator` (the demo path), and an experimental `MotionCrashDetector`
/// (stretch; the only type that imports Core Motion).
///
/// ## Contract (non-negotiable; see privacy steering)
/// - **On-device.** Detection runs entirely on the device and never makes a
///   network request. A detector must not import networking APIs.
/// - **Non-blocking.** `start()` / `stop()` return immediately and any heavy
///   signal processing stays off the main actor. The detector must never block,
///   slow, or stop ride recording.
/// - **Never stops recording.** A detector failure degrades to "no signal";
///   ride recording is unaffected (Requirement 5.8).
/// - **No camera access.** Detection never opens a capture session or requests
///   camera permission. (Camera APIs are confined to `Services/Detection`.)
/// - **Footage never leaves the device.** A detector does not upload, link, or
///   transmit any captured data; pre-crash footage (future) stays on-device via
///   `FootageBuffer`.
/// - **Experimental.** Detection cannot guarantee detection or delivery; copy
///   frames it as experimental and never claims reliability.
///
/// `onSignal` is delivered on the main actor (default MainActor isolation), so
/// the coordinator can react without hopping actors. `AnyObject` because a
/// detector is a long-lived reference type owning any system resources.
protocol CrashDetector: AnyObject {
    /// Invoked on the main actor when a probable crash is detected. The
    /// coordinator decides whether to act (it may be disarmed, suppressed, or
    /// capped — the detector never makes that decision).
    var onSignal: ((CrashSignal) -> Void)? { get set }

    /// Begin monitoring. Returns immediately; must never block recording.
    func start()

    /// Stop monitoring and release any system resources. Idempotent.
    func stop()
}
