import Foundation

/// An in-memory `WireLink` for tests (watch-companion design "fakes and the
/// loopback pair"; Requirement 21.2). Records everything sent, lets a test set
/// reachability and inject a reply, and drives its own callbacks. On its own it
/// has no peer — use it to assert what a layer above sent, or connect two of
/// them with `LoopbackWireLinkPair` for an end-to-end test.
public actor FakeWireLink: WireLink {
    public private(set) var activated = false
    public private(set) var sent: [WireEnvelope] = []
    public private(set) var contexts: [WireEnvelope] = []
    public private(set) var transfers: [WireEnvelope] = []
    private var reachable: Bool
    /// A reply the next `send` should return, if the loopback pair does not set one.
    public var stubbedReply: WireEnvelope?
    /// When true, every `send` reports `.unreachable` (ignoring `reachable`).
    public var forceUnreachable = false

    private var liveHandler: (@Sendable (WireEnvelope) -> WireEnvelope?)?
    private var contextHandler: (@Sendable (WireEnvelope) -> Void)?
    private var queuedHandler: (@Sendable (WireEnvelope) -> Void)?
    private var reachabilityHandler: (@Sendable (Bool) -> Void)?

    public init(reachable: Bool = true) {
        self.reachable = reachable
    }

    // MARK: WireLink

    public func activate() async { activated = true }

    public func onLiveMessage(_ handler: @escaping @Sendable (WireEnvelope) -> WireEnvelope?) async {
        liveHandler = handler
    }
    public func onContext(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {
        contextHandler = handler
    }
    public func onQueued(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {
        queuedHandler = handler
    }
    public func onReachabilityChange(_ handler: @escaping @Sendable (Bool) -> Void) async {
        reachabilityHandler = handler
    }

    public func send(_ envelope: WireEnvelope) async -> WireSendResult {
        sent.append(envelope)
        if forceUnreachable || !reachable { return .unreachable }
        return .delivered(reply: stubbedReply)
    }

    public func updateContext(_ envelope: WireEnvelope) async -> WireSendResult {
        contexts.append(envelope)
        return reachable ? .delivered(reply: nil) : .queued
    }

    public func transfer(_ envelope: WireEnvelope) async -> WireSendResult {
        transfers.append(envelope)
        return .queued
    }

    public var isReachable: Bool { reachable }

    // MARK: Test driving

    /// Change reachability and fire the callback.
    public func setReachable(_ value: Bool) {
        reachable = value
        reachabilityHandler?(value)
    }

    /// Deliver an envelope to this link's live handler, returning any reply.
    @discardableResult
    public func deliverLive(_ envelope: WireEnvelope) -> WireEnvelope? {
        liveHandler?(envelope)
    }

    /// Deliver an envelope to this link's context handler.
    public func deliverContext(_ envelope: WireEnvelope) {
        contextHandler?(envelope)
    }

    /// Deliver an envelope to this link's queue handler.
    public func deliverQueued(_ envelope: WireEnvelope) {
        queuedHandler?(envelope)
    }

    /// The most recent live send, if any.
    public var lastSent: WireEnvelope? { sent.last }

    /// Set the reply the next `send` returns (actor-isolated setter so a test
    /// can configure it with `await`).
    public func setStubbedReply(_ reply: WireEnvelope?) {
        stubbedReply = reply
    }

    /// Force every `send` to report `.unreachable`.
    public func setForceUnreachable(_ value: Bool) {
        forceUnreachable = value
    }
}
