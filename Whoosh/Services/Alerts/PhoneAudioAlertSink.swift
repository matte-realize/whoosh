import Foundation

/// A phone-speaker `AlertSink` for the routed alert kinds (rear-camera spec task
/// 29, Requirements 13.3–13.5, 6.7; design "Eyes-free surfaces: routing table").
/// It is the no-watch fallback channel: a short, distinct tone for the
/// rear-vehicle cue and camera/clip notices, plus a cautionary haptic (useful
/// only when the phone is in a pocket, not seat-mounted). All `AVAudioSession`
/// work stays behind the existing `TonePlaying`/`HapticPlaying` seams in
/// `Services/Alerts/`.
///
/// ## Contract (`AlertSink`)
/// - **Non-blocking.** `deliver` hands off to the tone/haptic players, which do
///   their own off-hot-path work, and returns immediately. Recording is never
///   delayed.
/// - **Isolated failure.** The players fail silently; `deliver` never throws.
/// - **On-device.** It touches no network and no camera.
///
/// Honesty (privacy steering): these are experimental cues; the speaker is
/// wind-limited and Whoosh cannot guarantee detection or delivery. The sink only
/// plays a sound — it never claims anything was captured.
///
/// `@MainActor` to match the `FanOutAlertManager` that drives it.
@MainActor
final class PhoneAudioAlertSink: AlertSink {
    let channel: AlertChannel
    /// The phone speaker is always considered available (the tone player fails
    /// silently if the route is unavailable).
    var isAvailable: Bool { true }

    private let tone: TonePlaying
    private let haptics: HapticPlaying

    init(
        channel: AlertChannel = .phoneSpeaker,
        tone: TonePlaying? = nil,
        haptics: HapticPlaying? = nil
    ) {
        self.channel = channel
        self.tone = tone ?? AudioSessionTonePlayer()
        self.haptics = haptics ?? CoreHapticsPlayer()
        self.haptics.prepare()
    }

    func deliver(_ kind: AlertKind, context: AlertDeliveryContext) throws {
        // Every routed kind gets the short cue tone; the rear-vehicle caution
        // additionally gets a haptic (helpful only for a pocketed phone). A
        // seat-mounted phone relies on the audio cue.
        switch kind {
        case .cautionRearVehicle:
            haptics.playCaution()
            tone.playCautionTone()
        case .cameraInterrupted, .cameraStopped, .phoneBatteryLow,
             .cameraResumed, .clipSaved, .clipNotSaved,
             .watchDisconnected, .watchReconnected:
            tone.playCautionTone()
        }
    }
}
