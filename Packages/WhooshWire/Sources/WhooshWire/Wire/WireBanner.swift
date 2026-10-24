import Foundation

/// The ride banner code carried in `WireRideStatus.banner` (watch-companion
/// design; MVP `RideBanner` kinds as codes, no message text; Requirement 8.4).
/// Unknown values decode to `.unknown`.
public enum WireBanner: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case signalLost
    case permissionRevoked
    case failed
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireBanner(rawValue: raw) ?? .unknown
    }
}
