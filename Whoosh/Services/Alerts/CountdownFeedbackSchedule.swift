import Foundation

/// The pure, framework-free scheduling logic for the crash countdown's audible
/// and spoken feedback (spec Requirement 8.6, design "Countdown screen" →
/// Audio/VoiceOver rows). Isolated here so it is unit-testable without
/// `AVAudioSession`, speech, or haptics; `SystemCountdownFeedback` consumes it.
///
/// Foundation-only value type; `Sendable`. All decisions are pure functions of
/// `remaining` (whole seconds) and `totalSeconds`.
///
/// Rules (from the design):
/// - A **per-second tone** plays in the last 10 seconds (`remaining` in 1...10).
/// - A **warning haptic** fires once per second for every tick (`remaining ≥ 1`).
/// - A **spoken final warning** is given in the last 5 seconds (`remaining` in
///   1...5), announcing each second.
/// - Periodic **spoken/VoiceOver milestones** occur at the start and every 10 s
///   (`remaining` a positive multiple of 10 below `totalSeconds`), so a 30 s
///   countdown announces at 20 s and 10 s (the start prompt covers 30 s).
struct CountdownFeedbackSchedule: Sendable {
    let totalSeconds: Int

    init(totalSeconds: Int) {
        self.totalSeconds = max(0, totalSeconds)
    }

    /// Whether a per-second tone should play at `remaining` seconds left.
    func shouldPlayTone(remaining: Int) -> Bool {
        remaining >= 1 && remaining <= 10
    }

    /// Whether a warning haptic should fire at `remaining` seconds left.
    func shouldFireHaptic(remaining: Int) -> Bool {
        remaining >= 1
    }

    /// Whether a spoken per-second final warning should be given at `remaining`.
    func shouldSpeakFinalWarning(remaining: Int) -> Bool {
        remaining >= 1 && remaining <= 5
    }

    /// Whether a periodic spoken/VoiceOver milestone should be announced at
    /// `remaining`. The start (`remaining == totalSeconds`) is covered by the
    /// opening prompt, so this covers the every-10-second interior marks only
    /// (excluding the final-warning band handled by `shouldSpeakFinalWarning`).
    func shouldAnnounceMilestone(remaining: Int) -> Bool {
        guard remaining >= 1, remaining < totalSeconds else { return false }
        guard remaining > 5 else { return false }
        return remaining % 10 == 0
    }
}
