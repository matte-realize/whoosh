import Foundation
@preconcurrency import WatchConnectivity
import WhooshWire
#if os(watchOS)
import WatchKit
#endif

/// The watch-side `WireLink` transport over `WCSession` (watch-companion spec
/// task 17; design "Channels and the wire contract"; Requirement 5.1, 5.8,
/// 10.2). This is the **only** watch file that may import `WatchConnectivity`
/// (enforced by `scripts/privacy-check.sh` rule 14); all policy, encode/decode,
/// and state decisions live above it in the pure `WhooshWire` layers.
///
/// Symmetric with the phone adapter, with two watch-specific duties:
///
/// 1. **Background-task completion.** watchOS wakes the app with a
///    `WKWatchConnectivityRefreshBackgroundTask` whenever queued content
///    (application context or `transferUserInfo`) arrives while the app is not
///    frontmost. Each such task **must** be marked completed or the app's
///    background runtime budget is exhausted and the system stops delivering.
///    The app delegate forwards those tasks to `register(_:)`; the adapter holds
///    them until it has drained the pending WC content (`hasContentPending`
///    false after a state change / handling pass) and then completes every one
///    on the main actor. Tasks that arrive with nothing pending are completed
///    immediately.
/// 2. **Companion-installed fact.** The watch reports whether the companion iOS
///    app is installed via `isCompanionAppInstalled`.
///
/// Delegate callbacks (on WC's private queue) hop onto an explicit `actor`
/// (`Inbox`) so the handler closures are race-free before re-entering the
/// `WireLink` callbacks; background-task bookkeeping is kept on the main actor
/// because `WKExtendedRuntimeSession`/`WKRefreshBackgroundTask` completion is
/// main-actor API.
///
/// _Pending task 1 spike:_ the on-device feasibility spike (tasks.md task 1) has
/// not been run. The approved O-W2 design (a cycling workout-session keep-alive,
/// fallback-ladder rung F0) is the path this adapter targets: the workout keeps
/// the app alive during a ride, while this link also survives suspension/wake
/// through background-task completion. Re-confirm the completion timing (drain
/// then complete) against the spike's T3/T4/T9 results in `spike-results.md`.
nonisolated final class WCSessionWireLink: NSObject, WireLink, @unchecked Sendable {

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
            try session.updateApplicationContext(["e": data])
            return session.isReachable ? .delivered(reply: nil) : .queued
        } catch {
            return .failed(code: "context")
        }
    }

    func transfer(_ envelope: WireEnvelope) async -> WireSendResult {
        guard let session, isSupported else { return .failed(code: "unsupported") }
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

    // MARK: - Facts (watch observes companion installation)

    /// Whether the companion iOS app is installed on the paired iPhone.
    var isCompanionAppInstalled: Bool { session?.isCompanionAppInstalled ?? false }

    // MARK: - Background-task completion (watchOS)

    #if os(watchOS)
    /// WC background tasks waiting to be completed once pending content drains.
    @MainActor private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    /// Forward a WC background task from the app delegate. If no WC content is
    /// still pending, complete it immediately; otherwise hold it until the next
    /// activation-state/receipt pass drains the queue.
    @MainActor
    func register(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        if canCompleteNow {
            task.setTaskCompletedWithSnapshot(false)
        } else {
            pendingTasks.append(task)
        }
    }

    /// Complete every held WC background task. Called after a receipt or an
    /// activation-state change once the session reports no content is pending.
    @MainActor
    func completePendingBackgroundTasksIfDrained() {
        guard canCompleteNow, !pendingTasks.isEmpty else { return }
        let tasks = pendingTasks
        pendingTasks.removeAll()
        for task in tasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    /// True when the session is active and has no remaining WC content to
    /// deliver, so a background task can be completed safely.
    @MainActor
    private var canCompleteNow: Bool {
        guard let session else { return true }
        guard session.activationState == .activated else { return false }
        return !session.hasContentPending
    }

    private func drainBackgroundTasks() {
        Task { @MainActor in completePendingBackgroundTasksIfDrained() }
    }
    #else
    private func drainBackgroundTasks() {}
    #endif

    // MARK: - Helpers

    private static func sendFailure(from error: Error) -> WireSendResult {
        if (error as NSError).code == WCError.Code.notReachable.rawValue {
            return .unreachable
        }
        return .failed(code: "send")
    }

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
        // An activation-state change may have drained queued content: a good
        // moment to complete any held background task.
        drainBackgroundTasks()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { await inbox.reachability(reachable) }
    }

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

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["e"] as? Data,
           let envelope = try? WireCodec.decodeEnvelope(data) {
            Task { await inbox.context(envelope) }
        }
        // Content handled; complete any background task that woke us for it.
        drainBackgroundTasks()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["e"] as? Data,
           let envelope = try? WireCodec.decodeEnvelope(data) {
            Task { await inbox.queued(envelope) }
        }
        drainBackgroundTasks()
    }
}
