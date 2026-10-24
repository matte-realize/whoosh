import Foundation

/// The result reported by the watch for an alert (watch-companion design
/// "`WireAlertReceipt`"; Requirement 12.3, 13.1). Drives the phone's escalation
/// decision. Unknown values decode to `.unknown`.
public enum WireAlertReceiptResult: String, Codable, Equatable, Sendable, CaseIterable {
    case played
    case suppressedRate
    case suppressedStale
    case suppressedDuplicate
    case suppressedNotActive
    case suppressedDemo
    case suppressedHigherTier
    case suppressedDisabled
    case failed
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireAlertReceiptResult(rawValue: raw) ?? .unknown
    }
}
