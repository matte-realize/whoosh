import Foundation

/// The pure, framework-free decision logic for the crash countdown's **VoiceOver
/// announcements** (spec Requirement 8.3 / 18.3, design "Countdown screen" →
/// VoiceOver row, crash-response task 20: "VoiceOver announcements at start,
/// every 10 s, and the last 5 s").
///
/// Isolated here so the announcement cadence and phrasing are unit-testable
/// without SwiftUI or UIKit accessibility. The countdown view consumes it to
/// decide, on each per-second tick, whether to post an accessibility
/// announcement and what to say. Distinct from `CountdownFeedbackSchedule`
/// (which governs audible tones and haptics): a VoiceOver user may have audio
/// cues muted, so the spoken-accessibility cadence is defined separately.
///
/// Foundation-only value type; `Sendable`. All decisions are pure functions of
/// `remaining` (whole seconds left) and `totalSeconds`.
///
/// Cadence (from the design):
/// - **Start** — announce once when the countdown appears (`remaining ==
///   totalSeconds`).
/// - **Every 10 s** — announce at each interior positive multiple of 10
///   (e.g. a 30 s countdown announces at 20 s and 10 s). The last-5-s band is
///   handled by its own rule so a 10-mark that also falls in 1...5 is not
///   duplicated.
/// - **Last 5 s** — announce each of the final five seconds (`remaining` in
///   1...5) so the rider knows the alert is about to send.
///
/// Honest copy: the announcement never claims a crash is confirmed, never says
/// emergency services are involved, and frames the action as "sending an alert"
/// — Whoosh cannot guarantee detection or delivery.
struct CountdownAnnouncementSchedule: Sendable {
    let totalSeconds: Int

    init(totalSeconds: Int) {
        self.totalSeconds = max(0, totalSeconds)
    }

    /// Whether a VoiceOver announcement should be posted at `remaining` seconds.
    ///
    /// `true` at the start, at interior 10-second marks, and in the last five
    /// seconds; `false` otherwise and once the countdown has reached zero.
    func shouldAnnounce(remaining: Int) -> Bool {
        guard remaining >= 1 else { return false }
        if remaining == totalSeconds { return true }          // start
        if remaining >= 1 && remaining <= 5 { return true }    // last 5 s
        guard remaining < totalSeconds else { return false }
        return remaining % 10 == 0                             // every 10 s (interior)
    }

    /// The announcement string for `remaining` seconds, or `nil` when no
    /// announcement is due. Phrasing is honest and VoiceOver-friendly.
    ///
    /// - Start: "Crash detected. Sending an alert in N seconds. Tap I'm OK to
    ///   cancel."
    /// - Interior / 10-second marks: "N seconds until the alert is sent."
    /// - Last 5 s: "N" (just the count, kept terse for the final urgency), with
    ///   "1 second" / "N seconds" wording at the 1 boundary.
    func announcement(remaining: Int) -> String? {
        guard shouldAnnounce(remaining: remaining) else { return nil }
        if remaining == totalSeconds {
            return "Crash detected. Sending an alert in \(remaining) seconds. Tap I'm OK to cancel."
        }
        if remaining <= 5 {
            return remaining == 1 ? "1 second" : "\(remaining) seconds"
        }
        return "\(remaining) seconds until the alert is sent."
    }
}
