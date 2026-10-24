import Foundation

/// The crash sub-object of `WireRideStatus.crash` (watch-companion design).
///
/// Carries the countdown event id, the **relative** remaining time
/// (`remainingMs`, skew-free; design time rule L3), a drill flag, a **contact
/// count** (never names or numbers; Requirement 15.2, 19.1), and the phase.
/// Absent from status when no countdown is active.
public struct WireCrashStatus: Equatable, Codable, Sendable {
    public var eventId: String
    public var remainingMs: Int
    public var isDrill: Bool
    public var contactCount: Int
    public var phase: WireCrashPhase

    public init(
        eventId: String,
        remainingMs: Int,
        isDrill: Bool,
        contactCount: Int,
        phase: WireCrashPhase
    ) {
        self.eventId = eventId
        self.remainingMs = remainingMs
        self.isDrill = isDrill
        self.contactCount = contactCount
        self.phase = phase
    }
}
