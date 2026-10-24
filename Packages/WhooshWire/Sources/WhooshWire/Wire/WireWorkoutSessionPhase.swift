import Foundation

/// The watch workout-session phase reported in `WireWatchState.session`
/// (watch-companion design "`WireWatchState`"; Requirement 4). A `failed` or
/// `unavailable` phase carries a reason in `WireWatchState.sessionReason`.
/// Unknown values decode to `.unknown`.
public enum WireWorkoutSessionPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case authorizing
    case preparing
    case running
    case paused
    case stopping
    case failed
    case unavailable
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireWorkoutSessionPhase(rawValue: raw) ?? .unknown
    }
}
