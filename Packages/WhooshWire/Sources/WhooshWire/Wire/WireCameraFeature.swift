import Foundation

/// Whether the rear-camera feature is on for the ride (watch-companion design
/// `WireRideStatus.camera.feature`). Unknown values decode to `.unknown`.
public enum WireCameraFeature: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case on
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCameraFeature(rawValue: raw) ?? .unknown
    }
}
