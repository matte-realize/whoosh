import Foundation

/// Events driving the `WireLinkStateMachine` (watch-companion design "Link state
/// machine"). Produced by the real transport (the WatchConnectivity adapter)
/// or, in tests,
/// by the `LoopbackWireLinkPair`.
public enum WireLinkEvent: Equatable, Sendable {
    /// The session finished activating. `paired` is meaningful on the phone
    /// only; `installed` means the counterpart app is installed.
    case activated(paired: Bool, installed: Bool)
    /// Activation failed.
    case activationFailed
    /// The session went inactive or was deactivated (phone lifecycle).
    case deactivated
    /// The watch's paired/installed facts changed (phone observes pairing).
    case watchStateChanged(paired: Bool, installed: Bool)
    /// Reachability toggled.
    case reachability(Bool)
    /// The peer's `hello` arrived.
    case helloReceived(WireHello)
    /// The hello handshake timed out (no peer hello within the window).
    case helloTimeout
    /// The peer relaunched (a new session nonce was observed).
    case peerRelaunched(nonce: String)
}
