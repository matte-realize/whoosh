import Foundation

/// A camera interruption / stop reason code (watch-companion design
/// `WireRideStatus.camera.reason` and `WireAlert.reason`; rear-camera
/// `CameraStopReason` codes). Text is rendered on the receiver from the code;
/// no raw framework text crosses the wire (Requirement 8.4, 19.1). Unknown
/// values decode to `.unknown`.
public enum WireCameraReason: String, Codable, Equatable, Sendable, CaseIterable {
    case thermal
    case storage
    case battery
    case permission
    case interrupted
    case failed
    case lockedScreen
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireCameraReason(rawValue: raw) ?? .unknown
    }
}
