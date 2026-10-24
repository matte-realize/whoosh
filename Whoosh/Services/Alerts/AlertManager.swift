import Foundation

/// The kind of alert the app can raise. Kept as a small enum that is open to
/// grow as detection matures (e.g. more hazard categories).
///
/// **Integration point for the alerts teammate.**
enum AlertKind: Equatable, Sendable {
    /// A cautionary cue that a vehicle may be approaching from the rear.
    case cautionRearVehicle
}

/// Abstraction for haptic/audio safety alerts.
///
/// **Integration point for the alerts teammate.** Implement this against the
/// abstraction; the ride-recording code does not need to change.
///
/// Contract (also see the design "Future seams" section):
/// - **On-device.** Alerts fire locally and must not depend on a network.
/// - **Non-blocking.** `fire(_:)` MUST return immediately and MUST never block,
///   slow, or stop ride recording. Any heavy haptic/audio session work is the
///   implementation's responsibility to keep off the hot path.
/// - **Honest.** Alerts are experimental cues, not a collision-prevention
///   guarantee.
///
/// The MVP ships only `StubAlertManager`, which does nothing.
protocol AlertManager {
    /// Fire an alert of the given kind. Must return immediately and never block
    /// or interrupt recording.
    func fire(_ kind: AlertKind)
}

/// The MVP's inert `AlertManager`: accepts `fire(_:)` and does nothing.
///
/// Injected at the composition root so the ride flow runs unchanged until a real
/// alert manager replaces it.
final class StubAlertManager: AlertManager {
    init() {}

    /// No-op: raises no haptic or audio alert.
    func fire(_ kind: AlertKind) {}
}
