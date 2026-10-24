import Foundation

/// A rider-initiated command from the watch (watch-companion design
/// "`WireCommand`"; Requirement 6). State-based (not a toggle); carries its own
/// `commandId` for idempotency, the target `rideId` (absent for `requestStart`),
/// `holdConfirmed` for the press-and-hold controls (`stop`/`requestStart`), the
/// `crashEventId` for a cancel, a skew-free `issuedAgoMs`, and the retry
/// `attempt` number.
public struct WireCommand: Equatable, Codable, Sendable {
    public var commandId: String
    public var kind: WireCommandKind
    public var rideId: String?
    public var holdConfirmed: Bool
    public var crashEventId: String?
    public var issuedAgoMs: Int
    public var attempt: Int

    public init(
        commandId: String,
        kind: WireCommandKind,
        rideId: String? = nil,
        holdConfirmed: Bool = false,
        crashEventId: String? = nil,
        issuedAgoMs: Int = 0,
        attempt: Int = 1
    ) {
        self.commandId = commandId
        self.kind = kind
        self.rideId = rideId
        self.holdConfirmed = holdConfirmed
        self.crashEventId = crashEventId
        self.issuedAgoMs = issuedAgoMs
        self.attempt = attempt
    }
}
