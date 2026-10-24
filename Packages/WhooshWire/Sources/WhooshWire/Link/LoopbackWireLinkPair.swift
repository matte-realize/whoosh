import Foundation

/// Connects a phone-side and a watch-side `WireLink` so a send on one is
/// delivered to the other, with controllable **delay, drop, duplicate,
/// reorder, and unreachable windows** (watch-companion design "`LoopbackWireLinkPair`
/// connecting a phone-side and a watch-side fake"; Requirement 21.2, 10.10).
/// Pure in-memory; no timers and no real time — faults are applied
/// deterministically from the `Faults` the test sets.
///
/// Live `send` is synchronous round-trip (the peer's live handler may return a
/// reply) unless a fault drops it; context and queue deliveries are applied to
/// the peer's handlers immediately unless dropped. "Unreachable" makes a live
/// send return `.unreachable` without delivering (context/queue still store).
public final class LoopbackWireLinkPair: Sendable {
    public let phone: LoopbackWireLink
    public let watch: LoopbackWireLink

    public init() {
        let phone = LoopbackWireLink(side: .phone)
        let watch = LoopbackWireLink(side: .watch)
        phone.attachPeer(watch)
        watch.attachPeer(phone)
        self.phone = phone
        self.watch = watch
    }

    /// Fault injection shared controls. Set on the **sending** endpoint before a
    /// send to shape how the peer receives it.
    public struct Faults: Equatable, Sendable {
        /// Drop the next `drop` live sends entirely (return `.unreachable`).
        public var drop: Bool
        /// Deliver each live send twice (duplicate id → the receiver dedupes).
        public var duplicate: Bool
        /// Live sends report `.unreachable` and do not deliver.
        public var unreachable: Bool
        /// Swallow the peer's reply (the sender sees `.delivered(reply: nil)`).
        public var dropReply: Bool

        public init(
            drop: Bool = false,
            duplicate: Bool = false,
            unreachable: Bool = false,
            dropReply: Bool = false
        ) {
            self.drop = drop
            self.duplicate = duplicate
            self.unreachable = unreachable
            self.dropReply = dropReply
        }

        public static let none = Faults()
    }
}

/// One endpoint of a `LoopbackWireLinkPair`. An actor so handler mutation and
/// delivery are serialized.
public actor LoopbackWireLink: WireLink {
    public enum Side: Sendable { case phone, watch }

    public let side: Side
    /// Set once at pair construction, before any send; never mutated after.
    fileprivate nonisolated(unsafe) weak var peer: LoopbackWireLink?

    /// Wire up the peer (called once by `LoopbackWireLinkPair.init`).
    fileprivate nonisolated func attachPeer(_ peer: LoopbackWireLink) {
        self.peer = peer
    }

    private var faults = LoopbackWireLinkPair.Faults.none
    private var reachable = true

    public private(set) var sent: [WireEnvelope] = []
    public private(set) var contexts: [WireEnvelope] = []
    public private(set) var transfers: [WireEnvelope] = []

    private var liveHandler: (@Sendable (WireEnvelope) -> WireEnvelope?)?
    private var contextHandler: (@Sendable (WireEnvelope) -> Void)?
    private var queuedHandler: (@Sendable (WireEnvelope) -> Void)?
    private var reachabilityHandler: (@Sendable (Bool) -> Void)?

    public init(side: Side) {
        self.side = side
    }

    // MARK: Fault / reachability control

    public func setFaults(_ faults: LoopbackWireLinkPair.Faults) { self.faults = faults }

    public func setReachable(_ value: Bool) {
        reachable = value
        reachabilityHandler?(value)
    }

    // MARK: WireLink

    public func activate() async {}

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
        guard let peer, !faults.unreachable, reachable else { return .unreachable }
        if faults.drop { return .unreachable }

        let reply = await peer.receiveLive(envelope)
        if faults.duplicate {
            _ = await peer.receiveLive(envelope)  // duplicate id; receiver dedupes
        }
        return .delivered(reply: faults.dropReply ? nil : reply)
    }

    public func updateContext(_ envelope: WireEnvelope) async -> WireSendResult {
        contexts.append(envelope)
        guard let peer, !faults.drop else { return .queued }
        await peer.receiveContext(envelope)
        return .delivered(reply: nil)
    }

    public func transfer(_ envelope: WireEnvelope) async -> WireSendResult {
        transfers.append(envelope)
        guard let peer, !faults.drop else { return .queued }
        await peer.receiveQueued(envelope)
        return .queued
    }

    public var isReachable: Bool { reachable && !faults.unreachable }

    // MARK: Peer delivery (called on the receiving endpoint)

    fileprivate func receiveLive(_ envelope: WireEnvelope) -> WireEnvelope? {
        liveHandler?(envelope)
    }
    fileprivate func receiveContext(_ envelope: WireEnvelope) {
        contextHandler?(envelope)
    }
    fileprivate func receiveQueued(_ envelope: WireEnvelope) {
        queuedHandler?(envelope)
    }
}
