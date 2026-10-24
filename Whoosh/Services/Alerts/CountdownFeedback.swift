import Foundation

/// Why a countdown's feedback ended, passed to `CountdownFeedback.end(reason:)`
/// so the implementation can play (or skip) a final cue and release the audio
/// session. Distinct from the crash-event outcome enums in `Models/Crash`.
///
/// Foundation-only enum; `Equatable`, `Sendable`, `CaseIterable`.
enum CountdownFeedbackEndReason: String, Sendable, Equatable, CaseIterable {
    /// The rider cancelled the countdown ("I'm OK").
    case cancelled
    /// The deadline was reached and the alert is being sent.
    case expired
    /// The rider tapped "Send now".
    case sentNow
    /// Consent was revoked during the countdown.
    case consentRevoked
}

/// The audible / spoken / haptic feedback for a crash countdown (spec
/// Requirement 8.5–8.7, design "Countdown, feedback, and UI"). The coordinator
/// drives it with the countdown's progress; it is a separate seam from the
/// existing `AlertManager` so that teammate's code is untouched (design D20).
///
/// ## Contract
/// - **Accompanies visual, never replaces it.** Audio/haptics are additional
///   cues; the visual countdown is always present, so a silent device or a
///   failed audio session never hides the countdown (Requirement 8.5).
/// - **Degrade silently.** If audio, speech, or haptics fail, feedback degrades
///   to visual-only; a failure never blocks the countdown or the send.
/// - **Idempotent `end`.** Calling `end(reason:)` more than once is safe and
///   releases the audio session only once.
/// - **On-device.** No network; the countdown must work fully offline.
///
/// `AnyObject` because the system implementation is a long-lived reference type
/// owning an audio session and a haptic engine; all members run on the main
/// actor (default MainActor isolation).
protocol CountdownFeedback: AnyObject {
    /// Begin feedback for a countdown of `totalSeconds`: activate the audio
    /// session, speak the opening prompt, prepare haptics.
    func begin(totalSeconds: Int)

    /// Called once per second with the whole seconds remaining; plays the
    /// per-second tone/haptic and spoken milestones as appropriate.
    func tick(remaining: Int)

    /// End feedback: stop tones/haptics, speak any final cue for `reason`, and
    /// release the audio session. Idempotent.
    func end(reason: CountdownFeedbackEndReason)
}
