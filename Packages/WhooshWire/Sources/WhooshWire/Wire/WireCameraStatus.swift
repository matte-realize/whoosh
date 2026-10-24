import Foundation

/// The camera sub-object of `WireRideStatus` (watch-companion design
/// `WireRideStatus.camera`): feature on/off, recording state, and an optional
/// reason code. Counts and codes only — never frames, thumbnails, or clip ids
/// (Requirement 19.1).
public struct WireCameraStatus: Equatable, Codable, Sendable {
    public var feature: WireCameraFeature
    public var state: WireCameraState
    public var reason: WireCameraReason?

    public init(
        feature: WireCameraFeature,
        state: WireCameraState,
        reason: WireCameraReason? = nil
    ) {
        self.feature = feature
        self.state = state
        self.reason = reason
    }
}
