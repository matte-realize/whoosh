import Foundation

/// Phone battery sub-object of `WireRideStatus.phone` (watch-companion design).
/// Percentage (0…100) and charging flag only.
public struct WirePhoneState: Equatable, Codable, Sendable {
    public var batteryPct: Int
    public var charging: Bool

    public init(batteryPct: Int, charging: Bool) {
        self.batteryPct = batteryPct
        self.charging = charging
    }
}
