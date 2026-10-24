import Foundation

/// The MVP ride lifecycle state as carried on the wire (watch-companion design
/// `WireRideStatus.state`). Mirrors the app's `RideState` as plain codes; the
/// watch never decides a transition. Unknown values decode to `.unknown`.
public enum WireRideState: String, Codable, Equatable, Sendable, CaseIterable {
    case idle
    case recording
    case paused
    case signalLost
    case finished
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireRideState(rawValue: raw) ?? .unknown
    }
}
