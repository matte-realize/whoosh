import Foundation

/// A single wrist haptic cue (watch-companion design "Haptic catalog", L1;
/// Requirement 11.5). Cases are named exactly after the WatchKit haptic-type
/// values the watch target will play; the package stays Foundation-only and
/// never imports WatchKit, so mapping a cue to a system haptic type happens in
/// the single watch file `WhooshWatch/Services/Haptics/WKHapticPlayer.swift`.
///
/// Cue *meanings* (design "Selection rules"): `retry` = temporary failure
/// (interruption), `failure` = a stop, `directionDown` = a value dropped
/// (battery), `directionUp` = a value rose / threshold crossed (the rear cue),
/// `start` = recovery. Navigation cues (`navigationLeftTurn`/`Right`) are
/// deliberately **absent** so a position hint can never be confused with a
/// "turn" meaning (design: considered, rejected; Future).
public enum HapticCue: String, Codable, Equatable, Sendable, CaseIterable {
    case notification
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    case click
}
