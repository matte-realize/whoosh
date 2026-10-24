import Foundation

/// The watch's receipt for an alert, normally sent as the reply to the alert
/// (watch-companion design "`WireAlertReceipt`"; Requirement 12.3). Carries the
/// result, whether the keep-alive workout was active (diagnostic, L4), and how
/// long after receipt the pattern played.
public struct WireAlertReceipt: Equatable, Codable, Sendable {
    public var alertId: String
    public var result: WireAlertReceiptResult
    public var workoutActive: Bool
    public var playedAfterMs: Int?

    public init(
        alertId: String,
        result: WireAlertReceiptResult,
        workoutActive: Bool,
        playedAfterMs: Int? = nil
    ) {
        self.alertId = alertId
        self.result = result
        self.workoutActive = workoutActive
        self.playedAfterMs = playedAfterMs
    }
}
