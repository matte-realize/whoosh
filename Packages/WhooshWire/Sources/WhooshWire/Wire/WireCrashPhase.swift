import Foundation

/// The crash-countdown phase carried in `WireRideStatus.crash.phase` and in
/// `WireAlert`/`WireCommandReply` (watch-companion design; crash-response
/// phases). Unknown values decode to `.unknown`.
public enum WireCrashPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case countdown
    case cancelled
    case sending
    case queuedOffline
    case sent
    case failed
    case stale
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCrashPhase(rawValue: raw) ?? .unknown
    }
}
