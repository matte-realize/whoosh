import Foundation

/// A request to pin a clip around an event (rear-camera spec Requirement 6,
/// design "Pinning and ClipWindowPolicy"). The pure `ClipWindowPolicy` turns a
/// request into a `PinWindow`; the pre/post lengths come from `RideCameraTuning`
/// keyed by `reason`.
///
/// Foundation-only value type; `Equatable`, `Codable`, `Sendable`.
struct PinRequest: Equatable, Codable, Sendable {
    /// Why the clip is being pinned (selects the pre/post window).
    let reason: ClipReason
    /// The wall-clock instant the window centres on.
    let eventTime: Date
    /// A local-only event reference (near-miss id or crash-event id), if any.
    let eventRef: String?

    init(reason: ClipReason, eventTime: Date, eventRef: String?) {
        self.reason = reason
        self.eventTime = eventTime
        self.eventRef = eventRef
    }
}
