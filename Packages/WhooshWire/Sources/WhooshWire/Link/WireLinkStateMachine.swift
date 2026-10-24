import Foundation

/// The pure link-lifecycle state machine shared by both sides of the wire
/// (watch-companion design "Link state machine (`WireLinkStateMachine`)", the
/// 17-row table; Requirement 5.7–5.11, 10.10). Every row is a unit test
/// (LS-1…17).
///
/// The machine is a value type: `apply(_:)` mutates `state`, bumps the internal
/// hello-retry counter, and returns the ordered `WireLinkEffect`s the transport
/// should run. It performs no I/O and holds no framework type, so it tests with
/// `swift test`.
///
/// `side` distinguishes the phone (which can observe pairing, re-activate a
/// deactivated session, and sends a full status after the handshake) from the
/// watch (which sends its `watchState` and has no `notPaired`/`inactive` rows).
/// `localHello` supplies this build's version range for negotiation.
public struct WireLinkStateMachine: Equatable, Sendable {
    public enum Side: Equatable, Sendable {
        case phone
        case watch
    }

    public private(set) var state: WireLinkState
    public let side: Side
    public let localHello: WireHello
    /// How many `hello` tries have been made for the current reachable window.
    public private(set) var helloTries: Int
    /// The maximum hello retries before giving up (design row 10/11; default 3).
    public let maxHelloTries: Int
    /// The peer nonce last seen `ready`, so a relaunch is detected.
    public private(set) var peerNonce: String?

    public init(
        side: Side,
        localHello: WireHello,
        maxHelloTries: Int = 3,
        state: WireLinkState = .activating
    ) {
        self.side = side
        self.localHello = localHello
        self.maxHelloTries = maxHelloTries
        self.state = state
        self.helloTries = 0
        self.peerNonce = nil
    }

    /// Apply an event, returning the ordered effects. Undefined (state, event)
    /// pairs are a no-op (row 17): the state is unchanged and no effect runs.
    @discardableResult
    public mutating func apply(_ event: WireLinkEvent) -> [WireLinkEffect] {
        switch (state, event) {

        // Row 2: activating → activate the session is implicit in init; an
        // explicit (re)activation request is modelled by `activated`.

        // Row 3: activating, phone, not paired → notPaired.
        case let (.activating, .activated(paired, _)) where side == .phone && !paired:
            state = .notPaired
            return [.report]

        // Row 4: activating, paired ∧ not installed (phone) OR companion missing
        // (watch) → notInstalled.
        case let (.activating, .activated(paired, installed))
            where (side == .phone && paired && !installed) || (side == .watch && !installed):
            state = .notInstalled
            return [.report]

        // Row 6: activating, installed ∧ not reachable → installedUnreachable.
        case let (.activating, .activated(_, installed)) where installed:
            // installed but not reachable yet (reachability arrives separately).
            state = .installedUnreachable
            return [.startStalenessTimers]

        // Row 7: activating/installedUnreachable, became reachable → send hello.
        case (.activating, .reachability(true)),
             (.installedUnreachable, .reachability(true)):
            return beginHandshake()

        // Row 5: phone session went inactive/deactivated → inactive, re-activate.
        case (_, .deactivated) where side == .phone:
            state = .inactive
            return [.reactivate]

        // Row 8/9: hello received while awaiting it.
        case let (.reachableHelloPending, .helloReceived(peer)):
            return completeHandshake(with: peer)

        // Row 10/11: hello timeout.
        case (.reachableHelloPending, .helloTimeout):
            if helloTries < maxHelloTries {
                helloTries += 1                // count the resend (row 10)
                return [.sendHello]            // resend; stay pending
            } else {
                state = .installedUnreachable  // row 11
                return [.markNotResponding, .startStalenessTimers]
            }

        // Row 12: ready → reachability(false) → installedUnreachable.
        case (.ready, .reachability(false)):
            state = .installedUnreachable
            peerNonce = nil
            return [.startStalenessTimers, .announceAfterDelay]

        // Row 13: ready, peer relaunched with a new nonce → reset, resend.
        case let (.ready, .peerRelaunched(nonce)) where nonce != peerNonce:
            peerNonce = nonce
            return [.resetDedupe, .resendStatus, .resendCrashCountdown]

        // Row 14: notPaired/notInstalled, now installed → installedUnreachable.
        case let (.notPaired, .watchStateChanged(_, installed)) where installed,
             let (.notInstalled, .watchStateChanged(_, installed)) where installed:
            state = .installedUnreachable
            return [.startStalenessTimers]

        // Row 15: any, pairing/installation lost → notPaired / notInstalled.
        case let (_, .watchStateChanged(paired, installed))
            where (side == .phone && !paired) || !installed:
            state = (side == .phone && !paired) ? .notPaired : .notInstalled
            return [.channelUnavailable]

        // Row 16: incompatible, hello now overlaps → ready.
        case let (.incompatible, .helloReceived(peer)):
            if WireVersion.negotiate(local: localHello.versionRange, remote: peer.versionRange) != nil {
                return completeHandshake(with: peer)
            }
            return []   // still no overlap → no-op (row 17)

        // Activation failed from activating → treat as unsupported/unreachable
        // report (not a dedicated row, but must not crash).
        case (.activating, .activationFailed):
            state = .installedUnreachable
            return [.report]

        // Row 17: everything else is a no-op.
        default:
            return []
        }
    }

    // MARK: - Helpers

    private mutating func beginHandshake() -> [WireLinkEffect] {
        state = .reachableHelloPending
        helloTries = 1
        return [.sendHello]
    }

    private mutating func completeHandshake(with peer: WireHello) -> [WireLinkEffect] {
        guard WireVersion.negotiate(local: localHello.versionRange, remote: peer.versionRange) != nil else {
            state = .incompatible                        // row 9
            return [.reportIncompatible]
        }
        state = .ready(peer: peer)                       // row 8 / row 16
        peerNonce = peer.sessionNonce
        helloTries = 0
        let afterHandshake: WireLinkEffect = side == .phone ? .sendFullStatus : .sendWatchState
        return [.negotiate, afterHandshake, .resendCrashCountdown]
    }

    /// Whether the link is handshaken and ready.
    public var isReady: Bool {
        if case .ready = state { return true }
        return false
    }
}
