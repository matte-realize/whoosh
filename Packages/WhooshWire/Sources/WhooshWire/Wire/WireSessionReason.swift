import Foundation

/// A reason code for a `failed` or `unavailable` workout session phase
/// (watch-companion design `WireWatchState.sessionReason`). Unknown values
/// decode to `.unknown`.
public enum WireSessionReason: String, Codable, Equatable, Sendable, CaseIterable {
    case healthDenied
    case startFailed
    case anotherWorkout
    case systemEnded
    case lowBattery
    case orphanTimeout
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireSessionReason(rawValue: raw) ?? .unknown
    }
}
