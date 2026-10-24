import Foundation

/// A `CountdownFeedback` that produces no audio, speech, or haptics (spec design
/// "Service protocols"). Used where only the visual countdown is wanted (e.g.
/// previews) or when audible feedback is unavailable. Injected so the
/// coordinator always has a non-optional feedback seam.
///
/// Contains no `AVAudioSession`, speech, or haptic code.
final class NoopCountdownFeedback: CountdownFeedback {
    init() {}

    /// No-op: no audio session is activated.
    func begin(totalSeconds: Int) {}

    /// No-op: no tone or haptic is played.
    func tick(remaining: Int) {}

    /// No-op: nothing to release.
    func end(reason: CountdownFeedbackEndReason) {}
}
