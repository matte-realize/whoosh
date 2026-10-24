import Foundation

/// Decides whether a status update is sent live (`sendMessage`), written to
/// context (`updateApplicationContext`), or both, given the link state, whether
/// the watch display is active, and what triggered the update
/// (watch-companion design "`StatusTransportPolicy` (pure)" table;
/// Requirement 8.5, 8.6). Pure value type.
///
/// The watch reports `displayActive` in `WireWatchState`; the phone never
/// assumes it. Context writes are themselves throttled (at most one per
/// `contextMinIntervalMs`) except for a crash-phase change, which is exempt.
public struct StatusTransportPolicy: Sendable {
    public let tuning: WatchTuning

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// What triggered this status update.
    public enum Trigger: Equatable, Sendable {
        /// The status content changed.
        case stateChange
        /// The periodic heartbeat fired.
        case heartbeat
        /// The watch asked for an immediate refresh (wrist raise).
        case refreshRequest
        /// The crash countdown phase changed (exempt from the context cap).
        case crashPhaseChange
    }

    /// The transport decision.
    public struct Decision: Equatable, Sendable {
        /// Send a live `sendMessage` now.
        public var live: Bool
        /// Write/refresh `updateApplicationContext` now.
        public var context: Bool

        public init(live: Bool, context: Bool) {
            self.live = live
            self.context = context
        }

        public static let none = Decision(live: false, context: false)
    }

    /// Decide the transport for a status update.
    ///
    /// - Parameters:
    ///   - linkState: the current link state.
    ///   - displayActive: whether the watch display is currently active.
    ///   - trigger: what triggered the update.
    ///   - msSinceLastContext: ms since the last context write (for the cap).
    public func decide(
        linkState: WireLinkState,
        displayActive: Bool,
        trigger: Trigger,
        msSinceLastContext: Int
    ) -> Decision {
        // A crash-phase change always goes live + context, exempt from the cap,
        // even if the link is not ready (so the watch sees it as soon as it can).
        if trigger == .crashPhaseChange {
            return Decision(live: linkState.isReadyForLiveSend, context: true)
        }

        guard linkState.isReadyForLiveSend else {
            // Not ready: live sends are impossible; only context for a change.
            return Decision(live: false, context: trigger == .stateChange)
        }

        let contextAllowed = msSinceLastContext >= tuning.statusHeartbeatIdleMs

        switch (displayActive, trigger) {
        case (true, .stateChange):
            // Row 1: ready, active, change → live + context.
            return Decision(live: true, context: true)
        case (true, .heartbeat):
            // Row 2: ready, active, 5 s heartbeat → live + context (≤ 30 s).
            return Decision(live: true, context: contextAllowed)
        case (false, .stateChange):
            // Row 3: ready, off, change → context only.
            return Decision(live: false, context: true)
        case (false, .heartbeat):
            // Row 4: ready, off, 30 s heartbeat → context only.
            return Decision(live: false, context: true)
        case (_, .refreshRequest):
            // Row 5: ready, any, wrist raise → live immediately.
            return Decision(live: true, context: false)
        case (_, .crashPhaseChange):
            return Decision(live: true, context: true)   // handled above
        }
    }
}

private extension WireLinkState {
    /// Whether a live `sendMessage` can be attempted in this state.
    var isReadyForLiveSend: Bool {
        if case .ready = self { return true }
        return false
    }
}
