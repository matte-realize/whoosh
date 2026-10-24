import Foundation

/// The link lifecycle state shared by the phone and watch sides of the wire
/// (watch-companion design "Link state machine (`WireLinkStateMachine`)";
/// Requirement 5.7–5.11, 10). Pure value type; the real transports
/// (the per-side WatchConnectivity adapter) drive it with events and read it back.
///
/// `notPaired` is phone-only (the watch never observes pairing); both sides use
/// every other case. `ready(peer:)` carries the negotiated peer hello so the
/// channel evaluator and the session model can read the agreed version and
/// capabilities.
public enum WireLinkState: Equatable, Sendable {
    /// WatchConnectivity is not supported on this device; all sends are no-ops.
    case unsupported
    /// The session is activating.
    case activating
    /// Phone only: no watch is paired.
    case notPaired
    /// Paired but the companion app is not installed (or, on the watch, the
    /// companion iOS app is missing).
    case notInstalled
    /// Phone only: the session went inactive/deactivated and is re-activating.
    case inactive
    /// Installed but the counterpart is not currently reachable.
    case installedUnreachable
    /// Reachable; a `hello` has been sent and we await the peer's hello.
    case reachableHelloPending
    /// Handshake complete; the peer's hello is carried for version/capabilities.
    case ready(peer: WireHello)
    /// The version ranges do not overlap; one side must update.
    case incompatible
}
