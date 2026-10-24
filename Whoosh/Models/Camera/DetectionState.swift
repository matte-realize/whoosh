import Foundation

/// The observable state of the on-device rear-vehicle detector, surfaced to the
/// ride-screen camera chip so the rider knows whether detection is actually
/// running (rear-camera spec Requirement 18.3; design "HazardDetector seam
/// update"). It is **not** a promise of accuracy — detection is experimental and
/// cannot guarantee detection or delivery; this only reports the model's
/// readiness, never a claim about what it will catch.
///
/// Foundation-only value type (Models layer); `Equatable`, `Sendable`.
///
/// - `off`: detection is not running (rear camera off, ride not recording, or
///   paused/interrupted). The chip stays on the existing "Rear detection off".
/// - `loading`: the CoreML model is being loaded once (async) after rear camera
///   recording was enabled; frames that arrive first are dropped.
/// - `on`: the model is loaded and consuming frames while recording.
/// - `unavailable`: the model could not be loaded (missing/failed); recording
///   is unaffected and the chip says detection is unavailable — never silent.
enum DetectionState: Equatable, Sendable {
    case off
    case loading
    case on
    case unavailable
}
