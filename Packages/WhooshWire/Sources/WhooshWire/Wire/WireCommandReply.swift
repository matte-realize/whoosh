import Foundation

/// The phone's typed answer to a command (watch-companion design
/// "`WireCommandReply`"; Requirement 6.3, 7). Always embeds a fresh status so
/// the watch reconciles from the reply rather than guessing.
///
/// `reason` is present when `outcome` is `ignored` or `rejected`; `detail` is
/// the concrete result (saved/pending/cancelled/tooLate/…); `newRideId` is the
/// id of the ride a `requestStart` created.
public struct WireCommandReply: Equatable, Codable, Sendable {
    public var commandId: String
    public var outcome: WireCommandOutcome
    public var reason: WireCommandReason?
    public var detail: WireCommandDetail?
    public var newRideId: String?
    public var status: WireRideStatus

    public init(
        commandId: String,
        outcome: WireCommandOutcome,
        reason: WireCommandReason? = nil,
        detail: WireCommandDetail? = nil,
        newRideId: String? = nil,
        status: WireRideStatus
    ) {
        self.commandId = commandId
        self.outcome = outcome
        self.reason = reason
        self.detail = detail
        self.newRideId = newRideId
        self.status = status
    }
}
