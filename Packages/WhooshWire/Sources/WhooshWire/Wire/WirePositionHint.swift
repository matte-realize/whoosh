import Foundation

/// An optional coarse position hint on a rear-vehicle alert (watch-companion
/// design `WireAlert.hint`; Requirement 13.6). Changes the text only — never a
/// directional navigation cue (design "Selection rules"). Unknown values decode
/// to `.unknown`.
public enum WirePositionHint: String, Codable, Equatable, Sendable, CaseIterable {
    case left
    case center
    case right
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WirePositionHint(rawValue: raw) ?? .unknown
    }
}
