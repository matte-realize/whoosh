import Foundation

/// A transient phone condition flag carried in `WireRideStatus.flags`
/// (watch-companion design; rear-camera storage/thermal flags). Encoded as a
/// sorted array of codes on the wire. Unknown values decode to `.unknown`.
public enum WireStatusFlag: String, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case storageLow
    case phoneHot
    case lowPowerMode
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireStatusFlag(rawValue: raw) ?? .unknown
    }

    public nonisolated static func < (lhs: WireStatusFlag, rhs: WireStatusFlag) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
