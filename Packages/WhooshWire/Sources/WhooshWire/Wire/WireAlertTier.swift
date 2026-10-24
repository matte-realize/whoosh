import Foundation

/// The urgency tier of a wire alert (watch-companion design; Requirement 11.2).
/// A higher tier preempts a lower one on the wrist. Unknown values decode to
/// `.unknown`.
public enum WireAlertTier: String, Codable, Equatable, Sendable, CaseIterable {
    case critical
    case caution
    case notice
    case confirm
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireAlertTier(rawValue: raw) ?? .unknown
    }
}
