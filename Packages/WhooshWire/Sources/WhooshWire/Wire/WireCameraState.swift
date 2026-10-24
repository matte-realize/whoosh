import Foundation

/// The rear-camera recording state as carried on the wire (watch-companion
/// design `WireRideStatus.camera.state`; rear-camera `CameraRecordingState`
/// codes). Unknown values decode to `.unknown`.
public enum WireCameraState: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case preparing
    case recording
    case degraded
    case interrupted
    case stopped
    case failed
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCameraState(rawValue: raw) ?? .unknown
    }
}
