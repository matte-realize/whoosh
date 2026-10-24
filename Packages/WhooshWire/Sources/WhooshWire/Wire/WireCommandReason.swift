import Foundation

/// The reason code accompanying an `ignored` or `rejected` command outcome
/// (watch-companion design "`WireCommandReply`" reasons; Requirement 6, 7).
/// Unknown values decode to `.unknown`.
public enum WireCommandReason: String, Codable, Equatable, Sendable, CaseIterable {
    case staleRide
    case noActiveRide
    case holdRequired
    case notArmed
    case notReady
    case rideActive
    case debounced
    case cameraNotRecording
    case noCountdown
    case staleEvent
    case unsupportedVersion
    case unknownCommand
    case watchDisabled
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCommandReason(rawValue: raw) ?? .unknown
    }
}
