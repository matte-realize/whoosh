import Foundation

/// Derives the routing `WatchChannelState` from the link state and the watch's
/// reported `WireWatchState` (watch-companion design "`WatchChannelEvaluator`
/// (phone, pure)"; Requirement 13.2–13.7). Pure function; the fan-out routing
/// policy consumes the result.
///
/// Precedence follows the design table, top to bottom:
/// 1. the "Apple Watch alerts and controls" setting being off, or a
///    `notPaired` / `notInstalled` / `incompatible` link → `unavailable`;
/// 2. installed but not reachable → `unreachable`;
/// 3. reachable but no running/paused workout session → `foregroundOnly`;
/// 4. a single missing readiness capability → `degraded(reason:)`;
/// 5. otherwise → `ready`.
public struct WatchChannelEvaluator: Sendable {
    public let tuning: WatchTuning

    public init(tuning: WatchTuning = WatchTuning()) {
        self.tuning = tuning
    }

    /// Evaluate the channel.
    ///
    /// - Parameters:
    ///   - linkState: the current `WireLinkStateMachine` state.
    ///   - watch: the watch's last reported state, or `nil` if none yet.
    ///   - settingEnabled: the "Apple Watch alerts and controls" setting.
    public func evaluate(
        linkState: WireLinkState,
        watch: WireWatchState?,
        settingEnabled: Bool
    ) -> WatchChannelState {
        // 1. Unavailable: setting off, pairing/installation missing, incompatible.
        if !settingEnabled { return .unavailable }
        switch linkState {
        case .unsupported, .notPaired, .notInstalled, .incompatible:
            return .unavailable
        case .activating, .inactive, .installedUnreachable, .reachableHelloPending:
            // 2. Installed but not handshaken/reachable.
            return .unreachable
        case .ready:
            break
        }

        // From here the link is `ready`. Without a watch report we cannot tell
        // if a workout keeps it alive, so treat it as foreground-only.
        guard let watch else { return .foregroundOnly }

        // Health explicitly denied → degraded (watch + audio); haptics only
        // while on screen, but the alert still routes to the watch.
        if watch.healthAuthorized == false {
            return .degraded(reason: .healthDenied)
        }
        // Another workout is running (we did not start it).
        if watch.anotherWorkout {
            return .degraded(reason: .anotherWorkout)
        }

        let sessionRunning = watch.session == .running || watch.session == .paused
        switch watch.session {
        case .failed, .unavailable:
            return .degraded(reason: .sessionFailed)
        default:
            break
        }

        // 3. Reachable but no keep-alive session: foreground-only (degraded).
        guard sessionRunning else { return .foregroundOnly }

        // 4. Low watch battery while otherwise ready → degraded.
        if watch.batteryPct <= tuning.watchBatteryLowPct {
            return .degraded(reason: .watchBatteryLow)
        }

        // Haptics not armed yet (session running but player not ready) → still
        // degraded so the audio channel backs it up.
        guard watch.hapticsArmed else {
            return .degraded(reason: .sessionFailed)
        }

        // 5. Fully ready.
        return .ready
    }
}
