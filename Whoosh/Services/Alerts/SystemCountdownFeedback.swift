import AVFoundation
import CoreHaptics
import Foundation
import UIKit

/// The system `CountdownFeedback`: audible tones, spoken prompts, and warning
/// haptics for a crash countdown (spec Requirement 8.5–8.7, design "Countdown
/// screen"). This is the **only** file that configures `AVAudioSession`
/// (enforced by `scripts/privacy-check.sh`).
///
/// Behaviour:
/// - Activates an `AVAudioSession` with the `.playback` category and `.duckOthers`
///   so the countdown is audible with the silent switch on and ducks other audio.
/// - Speaks an opening prompt via `AVSpeechSynthesizer`, a per-second final
///   warning in the last 5 s, and periodic milestones (pure schedule in
///   `CountdownFeedbackSchedule`).
/// - Plays a per-second tone in the last 10 s and fires a warning haptic each
///   second (foreground only).
/// - `end(reason:)` is **idempotent**: it stops tones/haptics, speaks any final
///   cue, and releases (deactivates) the audio session exactly once.
/// - **Degrades silently:** any audio/speech/haptic failure is caught and
///   ignored so the visual countdown always continues (audio is never the only
///   signal).
///
/// Honest by design: this feedback cannot guarantee detection or delivery; it is
/// one of several cues around a one-tap cancel.
///
/// Main-actor isolated (default isolation): it owns UIKit/AVFoundation objects
/// and is driven by the main-actor coordinator.
final class SystemCountdownFeedback: CountdownFeedback {
    private let synthesizer = AVSpeechSynthesizer()
    private let schedule: (Int) -> CountdownFeedbackSchedule
    private var currentSchedule: CountdownFeedbackSchedule?
    private var hapticEngine: CHHapticEngine?
    private var sessionActive = false
    private var hasEnded = false
    /// The remaining value of the most recent tick, so repeated ticks for the
    /// same second do not double-fire tone/haptic cues.
    private var lastTickRemaining: Int?

    /// `scheduleFactory` is injectable so a test can construct the type with the
    /// pure schedule; the default is the production schedule.
    init(scheduleFactory: @escaping (Int) -> CountdownFeedbackSchedule = { CountdownFeedbackSchedule(totalSeconds: $0) }) {
        self.schedule = scheduleFactory
    }

    // MARK: CountdownFeedback

    func begin(totalSeconds: Int) {
        hasEnded = false
        lastTickRemaining = nil
        currentSchedule = schedule(totalSeconds)
        activateSession()
        prepareHaptics()
        speak("Crash detected. Sending an alert in \(totalSeconds) seconds. Tap I'm OK to cancel.")
    }

    func tick(remaining: Int) {
        guard !hasEnded, let schedule = currentSchedule else { return }
        guard lastTickRemaining != remaining else { return }
        lastTickRemaining = remaining

        if schedule.shouldFireHaptic(remaining: remaining) {
            fireWarningHaptic()
        }
        if schedule.shouldPlayTone(remaining: remaining) {
            playTone()
        }
        if schedule.shouldSpeakFinalWarning(remaining: remaining) {
            speak("\(remaining)")
        } else if schedule.shouldAnnounceMilestone(remaining: remaining) {
            speak("\(remaining) seconds")
        }
    }

    func end(reason: CountdownFeedbackEndReason) {
        guard !hasEnded else { return }
        hasEnded = true
        currentSchedule = nil
        lastTickRemaining = nil

        switch reason {
        case .cancelled:
            speak("Alert cancelled.")
        case .expired, .sentNow:
            speak("Sending alert now.")
        case .consentRevoked:
            break
        }

        stopHaptics()
        deactivateSession()
    }

    // MARK: Audio session (the only AVAudioSession use in the app)

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            // Degrade silently to visual-only; audio is never the only signal.
            sessionActive = false
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Ignore: releasing failed, nothing more to do.
        }
    }

    // MARK: Speech

    private func speak(_ text: String) {
        guard sessionActive else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    // MARK: Tone

    private func playTone() {
        // A short system tone as the per-second cue. Kept minimal and best-effort;
        // the visual countdown is authoritative.
        AudioServicesPlaySystemSound(1057)
    }

    // MARK: Haptics

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            hapticEngine = nil
            return
        }
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    private func fireWarningHaptic() {
        guard let engine = hapticEngine else { return }
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Degrade silently to visual-only.
        }
    }

    private func stopHaptics() {
        hapticEngine?.stop()
        hapticEngine = nil
    }
}
