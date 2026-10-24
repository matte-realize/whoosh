import Foundation

/// A side effect requested by the `WireLinkStateMachine` when it processes an
/// event (watch-companion design "Link state machine", Effects column). The
/// machine itself is pure and performs no I/O: it returns the effects so the
/// transport layer (the WatchConnectivity adapter) can run them. Order within
/// the returned
/// array is the order the design lists.
public enum WireLinkEffect: Equatable, Sendable {
    /// Report the new state (readiness UI / diagnostics).
    case report
    /// Activate the underlying session.
    case activate
    /// Re-activate after an inactive/deactivated transition (phone, L8).
    case reactivate
    /// Send a `hello` and arm the hello timeout.
    case sendHello
    /// Start the staleness timers for an unreachable/ready-lost link.
    case startStalenessTimers
    /// Negotiate the version from the peer hello.
    case negotiate
    /// Send a full status (phone side) after the handshake.
    case sendFullStatus
    /// Send a `watchState` (watch side) after the handshake.
    case sendWatchState
    /// Resend any active crash countdown so it survives a reconnect.
    case resendCrashCountdown
    /// Resend the latest status (after a peer relaunch).
    case resendStatus
    /// Reset the command-dedupe cache (the peer relaunched).
    case resetDedupe
    /// Mark the peer "app not responding" (hello retries exhausted).
    case markNotResponding
    /// Report which side must update (incompatible versions); phone channels
    /// carry alerts in the meantime.
    case reportIncompatible
    /// The channel is unavailable (pairing/installation lost).
    case channelUnavailable
    /// Announce the disconnection after the configured delay (Req 10.5).
    case announceAfterDelay
}
