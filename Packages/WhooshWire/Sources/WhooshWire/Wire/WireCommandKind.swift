import Foundation

/// The kind of a wrist command (watch-companion design "`WireCommand`";
/// Requirement 6.1). Unknown values decode to `.unknown` and are rejected by the
/// phone reducer (`unknownCommand`).
public enum WireCommandKind: String, Codable, Equatable, Sendable, CaseIterable {
    case pause
    case resume
    case saveClip
    case stop
    case cancelCrashCountdown
    case requestStart
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCommandKind(rawValue: raw) ?? .unknown
    }
}
