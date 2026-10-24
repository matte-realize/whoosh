import Foundation

/// The outcome class of a command reply (watch-companion design
/// "`WireCommandReply`"; Requirement 6.3, 7.2). The accompanying reason code
/// lives in `WireCommandReply.reason`. Unknown values decode to `.unknown`.
public enum WireCommandOutcome: String, Codable, Equatable, Sendable, CaseIterable {
    case accepted
    case alreadyInState
    case ignored
    case rejected
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCommandOutcome(rawValue: raw) ?? .unknown
    }
}
