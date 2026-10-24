import Foundation

/// A code explaining why a ride is not yet startable from the wrist
/// (watch-companion design `WireStartState.notReady`; Requirement 9.3). Rendered
/// as a short instruction on the watch. Unknown values decode to `.unknown`.
public enum WireStartReasonCode: String, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case notArmed
    case camera
    case location
    case rideActive
    case crashActive
    case linkNotReady
    case appNotActive
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireStartReasonCode(rawValue: raw) ?? .unknown
    }

    public nonisolated static func < (lhs: WireStartReasonCode, rhs: WireStartReasonCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
