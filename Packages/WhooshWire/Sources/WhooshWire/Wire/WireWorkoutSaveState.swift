import Foundation

/// How the workout ended with respect to Apple Health (watch-companion design
/// `WireWatchState.workoutSaved`; Requirement 16). Unknown values decode to
/// `.unknown`.
public enum WireWorkoutSaveState: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case saved
    case discarded
    case failed
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireWorkoutSaveState(rawValue: raw) ?? .unknown
    }
}
