import Foundation

/// The transport seam between the phone and watch (watch-companion design
/// "Channels and the wire contract"; Requirement 5.7–5.11, 10.10, 21.2). The
/// real implementation is the per-side WatchConnectivity adapter (one file per
/// side, the only files allowed to touch that framework); tests use
/// `FakeWireLink` and the
/// `LoopbackWireLinkPair`.
///
/// The link carries already-encoded `WireEnvelope`s; encoding/decoding and all
/// policy live above it. It exposes:
/// - `activate()` to start the session;
/// - callbacks for reachability and link-state changes, and for received
///   envelopes (live, context, and queue);
/// - a live send with a typed result and an optional reply envelope;
/// - a context update (latest-wins) and a queue transfer (ordered, must-arrive).
///
/// Methods are `async` so the real transport can hop actors; the fakes resolve
/// immediately (or after a controllable delay in the loopback pair).
public protocol WireLink: AnyObject, Sendable {
    /// Begin activation. Idempotent.
    func activate() async

    /// Set the callback invoked when a live envelope arrives (with the ability
    /// to return a reply envelope synchronously to the sender's `send`).
    func onLiveMessage(_ handler: @escaping @Sendable (WireEnvelope) -> WireEnvelope?) async

    /// Set the callback invoked when the counterpart writes application context.
    func onContext(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async

    /// Set the callback invoked when a queued transfer arrives.
    func onQueued(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async

    /// Set the callback invoked when reachability toggles.
    func onReachabilityChange(_ handler: @escaping @Sendable (Bool) -> Void) async

    /// Send a live message, awaiting a typed result that embeds any reply.
    func send(_ envelope: WireEnvelope) async -> WireSendResult

    /// Update the latest application context (coalesced, latest-wins).
    func updateContext(_ envelope: WireEnvelope) async -> WireSendResult

    /// Transfer a queued, ordered, must-arrive message.
    func transfer(_ envelope: WireEnvelope) async -> WireSendResult

    /// The current reachability.
    var isReachable: Bool { get async }
}

/// The typed outcome of a `WireLink` send (watch-companion design "live send
/// with a typed result and reply"; Requirement 5.8). Never throws: an
/// unreachable link or a transport error is a value, so callers always handle
/// failure explicitly.
public enum WireSendResult: Equatable, Sendable {
    /// Delivered; `reply` is the peer's synchronous reply envelope, if any.
    case delivered(reply: WireEnvelope?)
    /// Queued/stored for later (context or transfer accepted while unreachable).
    case queued
    /// The counterpart was not reachable for a live send.
    case unreachable
    /// A transport-level failure (encode/transport error); carries a short code.
    case failed(code: String)
}
