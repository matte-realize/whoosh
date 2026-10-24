import Foundation
@preconcurrency import WatchConnectivity
import WhooshWire

/// The phone-side `WireLink` transport over `WCSession` (watch-companion spec
/// task 16; design "Channels and the wire contract"; Requirement 5.1, 5.7, 5.8,
/// 10.3, 3.10). This is the **only** phone file that may import
/// `WatchConnectivity` (enforced by `scripts/privacy-check.sh`, rule 14); every
/// policy, encode/decode, and state decision lives above it in the pure layers.
///
/// It carries already-encoded `WireEnvelope`s both ways:
/// - **live send with a reply** (`send`) via `WCSession.sendMessageData` — the
///   watch's `messageData` reply handler produces the synchronous
///   `WireCommandReply`/`WireAlertReceipt` envelope the caller awaits;
/// - **latest-wins context** (`updateContext`) via
///   `WCSession.updateApplicationContext`, for the last ride status so a waking
///   watch always has the freshest snapshot;
/// - **ordered, must-arrive transfer** (`transfer`) via
///   `WCSession.transferUserInfo`, for summaries and replayed notices.
///
/// The `WCSessionDelegate` runs on a private queue; this adapter hops every
/// callback onto an explicit `actor` (`Inbox`) so the handler closures and the
/// outstanding-transfer bookkeeping are race-free, then re-enters the `WireLink`
/// callbacks. Reachability and installed/paired facts are read straight off the
/// session.
///
/// `startWatchApp` lives in `WatchLauncher`, not here (HealthKit confinement,
/// privacy rule 20); this file touches only `WatchConnectivity`.
///
/// _Pending task 1 spike:_ the on-device feasibility spike (tasks.md task 1) has
/// not yet been run. The approved O-W2 design (a cycling workout-session
/// keep-alive, confirmed as the fallback-ladder rung F0) is the path this
/// adapter is written for: WatchConnectivity carries the wire while the workout
/// session keeps the watch app alive. When the spike records its go decision in
/// `spike-results.md`, re-confirm the live/context/transfer split and the
/// outstanding-transfer cap below against the measured numbers.
nonisolated final class WCSessionWireLink: NSObject, WireLink, @unchecked Sendable {

    /// A short cap on outstanding `transferUserInfo` operations; stale ones are
    /// cancelled so a flaky link cannot pile up a backlog (design "Size and rate
    /// budgets"). Conservative until the spike measures the real throughput.
    private static let maxOutstandingTransfers = 8

    /// Serialises delegate callbacks and handler mutation off the WC queue.
    private actor Inbox {
        var liveHandler: (@Sendable (WireEnvelope) -> WireEnvelope?)?
        var contextHandler: (@Sendable (WireEnvelope) -> Void)?
        var queuedHandler: (@Sendable (WireEnvelope) -> Void)?
        var reachabilityHandler: (@Sendable (Bool) -> Void)?

        func setLive(_ h: @escaping @Sendable (WireEnvelope) -> WireEnvelope?) { liveHandler = h }
        func setContext(_ h: @escaping @Sendable (WireEnvelope) -> Void) { contextHandler = h }
        func setQueued(_ h: @escaping @Sendable (WireEnvelope) -> Void) { queuedHandler = h }
        func setReachability(_ h: @escaping @Sendable (Bool) -> Void) { reachabilityHandler = h }

        func live(_ env: WireEnvelope) -> WireEnvelope? { liveHandler?(env) }
        func context(_ env: WireEnvelope) { contextHandler?(env) }
        func queued(_ env: WireEnvelope) { queuedHandler?(env) }
        func reachability(_ value: Bool) { reachabilityHandler?(value) }
    }

    private let inbox = Inbox()
    private let session: WCSession?

    /// `true` when WatchConnectivity is supported on this device (always true on
    /// iPhone; the guard keeps the type usable in previews/tests on other
    /// destinations).
    private let isSupported: Bool

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
            self.isSupported = true
        } else {
            self.session = nil
            self.isSupported = false
        }
        super.init()
    }

    // MARK: - WireLink

    func activate() async {
        guard let session, isSupported else { return }
        session.delegate = self
        // Idempotent: WCSession ignores a repeat activate once active.
        if session.activationState != .activated {
            session.activate()
        }
    }

    func onLiveMessage(_ handler: @escaping @Sendable (WireEnvelope) -> WireEnvelope?) async {
        await inbox.setLive(handler)
    }

    func onContext(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {
        await inbox.setContext(handler)
    }

    func onQueued(_ handler: @escaping @Sendable (WireEnvelope) -> Void) async {
        await inbox.setQueued(handler)
    }

    func onReachabilityChange(_ handler: @escaping @Sendable (Bool) -> Void) async {
        await inbox.setReachability(handler)
    }

    func send(_ envelope: WireEnvelope) async -> WireSendResult {
        guard let session, isSupported else { return .failed(code: "unsupported") }
        guard session.isReachable else { return .unreachable }
        let data: Data
        do {
            data = try WireCodec.encodeToData(envelope)
        } catch {
            return .failed(code: "encode")
        }
        return await withCheckedContinuation { continuation in
            session.sendMessageData(
                data,
                replyHandler: { replyData in
                    let reply = try? WireCodec.decodeEnvelope(replyData)
                    continuation.resume(returning: .delivered(reply: reply))
                },
                errorHandler: { error in
                    continuation.resume(returning: Self.sendFailure(from: error))
                }
            )
        }
    }

    func updateContext(_ envelope: WireEnvelope) async -> WireSendResult {
        guard let session, isSupported else { return .failed(code: "unsupported") }
        do {
            let data = try WireCodec.encodeToData(envelope)
            // Latest-wins context survives a reachability gap and is replayed to
            // a waking watch, so an unreachable update is still "accepted".
            try session.updateApplicationContext(["e": data])
            return session.isReachable ? .delivered(reply: nil) : .queued
        } catch {
            return .failed(code: "context")
        }
    }

    func transfer(_ envelope: WireEnvelope) async -> WireSendResult {
        guard let session, isSupported else { return .failed(code: "unsupported") }
        // Cap the backlog: cancel the oldest outstanding transfers first.
        let outstanding = session.outstandingUserInfoTransfers
        if outstanding.count >= Self.maxOutstandingTransfers {
            let overflow = outstanding.count - Self.maxOutstandingTransfers + 1
            for transfer in outstanding.prefix(overflow) {
                transfer.cancel()
            }
        }
        do {
            let data = try WireCodec.encodeToData(envelope)
            session.transferUserInfo(["e": data])
            return .queued
        } catch {
            return .failed(code: "transfer")
        }
    }

    var isReachable: Bool {
        get async { session?.isReachable ?? false }
    }

    // MARK: - Facts (phone observes pairing + installation)

    /// Whether a watch is currently paired to this iPhone.
    var isPaired: Bool { session?.isPaired ?? false }

    /// Whether the Whoosh watch app is installed on the paired watch.
    var isWatchAppInstalled: Bool { session?.isWatchAppInstalled ?? false }

    // MARK: - Helpers

    private static func sendFailure(from error: Error) -> WireSendResult {
        // WCErrorCodeDeviceNotReachable maps to an unreachable value, not a
        // transport failure, so the caller falls back cleanly (Req 5.8).
        if (error as NSError).code == WCError.Code.notReachable.rawValue {
            return .unreachable
        }
        return .failed(code: "send")
    }

    /// Deliver a decoded live envelope to the handler and return any reply.
    private func dispatchLive(_ data: Data) async -> Data? {
        guard let envelope = try? WireCodec.decodeEnvelope(data) else { return nil }
        guard let reply = await inbox.live(envelope) else { return nil }
        return try? WireCodec.encodeToData(reply)
    }
}

// MARK: - WCSessionDelegate

extension WCSessionWireLink: @preconcurrency WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { await inbox.reachability(reachable) }
    }

    // Phone lifecycle: the session can deactivate when switching watches; it
    // must be re-activated so a new watch can connect (design link row 5).
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { await inbox.reachability(reachable) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // Pairing/installation changed; surface it through reachability so the
        // channel re-evaluates (the state machine reads isPaired/installed too).
        let reachable = session.isReachable
        Task { await inbox.reachability(reachable) }
    }

    // Live message with a reply (sendMessageData).
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        // WatchConnectivity's reply handler is not `Sendable`; it is invoked
        // exactly once from this task, so capture it through an unsafe box.
        nonisolated(unsafe) let reply = replyHandler
        Task {
            let replyData = await dispatchLive(messageData)
            reply(replyData ?? Data())
        }
    }

    // Latest-wins application context (status).
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["e"] as? Data,
              let envelope = try? WireCodec.decodeEnvelope(data) else { return }
        Task { await inbox.context(envelope) }
    }

    // Ordered, must-arrive transfer (summaries, replayed notices).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["e"] as? Data,
              let envelope = try? WireCodec.decodeEnvelope(data) else { return }
        Task { await inbox.queued(envelope) }
    }
}

// MARK: - PhoneRemoteFactory

/// Everything the composition root needs to make the watch live, built in the
/// one phone file allowed to name the WatchConnectivity session so
/// `AppEnvironment` never touches the framework (privacy rule 14).
///
/// - `remote` is the `RideRemoteControlling` the ride flow publishes to and
///   routes wrist commands through (a `WatchRideRemote` when a usable watch is
///   paired, else the inert `NoopRideRemote`).
/// - `statusHolder` is the mutable live snapshot the `WatchLiveCoordinator`
///   writes ~1 Hz; the remote reads it to publish and to decide commands.
/// - `watchLink` is the **same** `WireLink` the remote speaks over, shared so
///   the `WatchAlertSink` buzzes the wrist on the one activated session (`nil`
///   when no usable watch, so the alert fan-out stays phone-audio only).
@MainActor
struct PhoneRemoteComposition {
    let remote: RideRemoteControlling
    let statusHolder: WatchLiveStatusHolder
    let watchLink: (any WireLink)?
}

/// Builds the phone's eyes-free remote (watch-companion tasks 16/17; "make the
/// watch live"). Lives in the phone WatchConnectivity adapter file (the only
/// phone file allowed to name the connectivity session), so the composition root
/// (`AppEnvironment`) never touches the framework — it only receives a
/// `PhoneRemoteComposition`.
///
/// Selects a watch-backed `WatchRideRemote` over the phone adapter **only** when
/// an Apple Watch is paired and the Whoosh watch app is installed; otherwise the
/// inert `NoopRideRemote` and no link, so with no usable watch the phone behaves
/// exactly as before (nothing published, no command ever received, the alert
/// fan-out is phone-audio only — Requirement 1.5).
///
/// The `WatchRideRemote` is the richer remote: its snapshot carries the crash
/// sub-object and arming, so a crash countdown (real or a demo drill with no
/// active ride) reaches the wrist. Its snapshot closure reads the shared
/// `WatchLiveStatusHolder` the `WatchLiveCoordinator` keeps current.
@MainActor
enum PhoneRemoteFactory {
    static func make(clock: Clock) -> PhoneRemoteComposition {
        let link = WCSessionWireLink()
        guard link.isPaired, link.isWatchAppInstalled else {
            return PhoneRemoteComposition(
                remote: NoopRideRemote(),
                statusHolder: WatchLiveStatusHolder(),
                watchLink: nil
            )
        }
        let holder = WatchLiveStatusHolder()
        let remote = WatchRideRemote(link: link, clock: clock) {
            holder.current
        }
        return PhoneRemoteComposition(remote: remote, statusHolder: holder, watchLink: link)
    }
}
