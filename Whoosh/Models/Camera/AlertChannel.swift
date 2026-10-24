import Foundation

/// One output channel an alert can be delivered on (rear-camera spec
/// Requirement 13.3, design "Eyes-free surfaces: Routing table"). Each concrete
/// `AlertSink` owns exactly one channel; `AlertRoutingPolicy` returns an ordered
/// list of channels and the `FanOutAlertManager` delivers to the matching sinks.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Hashable`,
/// `Sendable`, `CaseIterable` so it keys cooldown maps and compares in tests.
enum AlertChannel: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    /// Apple Watch wrist haptic (plus short text) — the primary in-ride channel.
    case watchHaptic = "watch_haptic"
    /// Audio through connected headphones (clearer than the speaker in wind).
    case phoneHeadphones = "phone_headphones"
    /// Audio through the phone speaker (wind-limited; honest about the limit).
    case phoneSpeaker = "phone_speaker"
    /// Phone haptic — only useful when the phone is in a pocket (not seat-mounted).
    case phoneHaptic = "phone_haptic"
    /// A local notification — used when the phone is locked or backgrounded; it
    /// mirrors to a paired watch in that state.
    case localNotification = "local_notification"
}

/// The app's foreground/visibility state, which gates routing (rear-camera spec
/// design routing table columns). A stale rear-vehicle caution is dropped when
/// the phone is locked or backgrounded; camera notices fall back to a local
/// notification there.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum AppAlertState: String, Equatable, Codable, Sendable, CaseIterable {
    /// The app is foreground in ride mode (screen dim, touch-locked).
    case foregroundRideMode = "foreground_ride_mode"
    /// The app is foreground with the active-ride screen (ride mode off).
    case foregroundActiveScreen = "foreground_active_screen"
    /// The phone is locked or the app is backgrounded (no live in-app audio/haptic).
    case lockedOrBackgrounded = "locked_or_backgrounded"
}
