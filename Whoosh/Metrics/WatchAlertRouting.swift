import Foundation
import WhooshWire

/// The watch-channel-aware extension of `AlertRoutingPolicy` (watch-companion
/// spec task 9; design "Fan-out, routing, and escalation" table; Requirement
/// 12.1, 13.2–13.7, 13.9). Pure, framework-free (Metrics layer: Models +
/// Foundation + the Foundation-only `WhooshWire` package).
///
/// The rear-camera `AlertRoutingPolicy.route(_:context:tuning:)` chooses channels
/// from a flat `availableChannels` set. This extension layers the **watch
/// channel state** on top: the watch is the primary route when `ready`, watch
/// **and** audio when `degraded`/`foregroundOnly`, phone channels only when
/// `unavailable`/`unreachable`, and the crash countdown goes to every channel.
/// It produces a `Plan` of ordered steps the `FanOutAlertManager` executes and
/// says whether audio should accompany a watch cue (escalation vs. concurrent).
extension AlertRoutingPolicy {

    /// A routing plan for one alert given the watch channel state.
    struct Plan: Equatable, Sendable {
        /// The channels delivered to immediately, in order.
        var immediate: [AlertChannel]
        /// A channel to escalate to if the watch does not acknowledge within the
        /// ack timeout (nil when there is nothing to escalate to, or when audio
        /// already plays immediately).
        var escalateTo: AlertChannel?

        init(immediate: [AlertChannel], escalateTo: AlertChannel? = nil) {
            self.immediate = immediate
            self.escalateTo = escalateTo
        }

        static let empty = Plan(immediate: [])

        /// Whether the plan buzzes the watch at all (drives outcome tracking).
        var usesWatch: Bool { immediate.contains(.watchHaptic) }
    }

    /// Build a routing plan for `kind` given the watch channel state, the app's
    /// visibility, the available audio channels, and the "also play a sound"
    /// setting.
    ///
    /// - Parameters:
    ///   - kind: the alert kind.
    ///   - watch: the phone's view of the watch channel.
    ///   - appState: the phone's foreground/visibility state.
    ///   - audioAvailable: the audio channels available right now
    ///     (`phoneHeadphones` and/or `phoneSpeaker`), in preference order.
    ///   - alsoPlaySound: the "Also play a sound" setting (O-W7). When on, audio
    ///     plays **concurrently** with a confirmed watch cue rather than only on
    ///     escalation.
    ///   - tier: the urgency tier to route by. Defaults to `kind.tier`; the
    ///     crash countdown supplies `.critical` out of band via its
    ///     `AlertContext` so every channel is used.
    static func plan(
        for kind: AlertKind,
        watch: WatchChannelState,
        appState: AppAlertState,
        audioAvailable: [AlertChannel],
        alsoPlaySound: Bool = false,
        tier: AlertTier? = nil
    ) -> Plan {
        let locked = appState == .lockedOrBackgrounded
        let audio = audioAvailable.filter { $0 == .phoneHeadphones || $0 == .phoneSpeaker }
        let bestAudio = audio.first
        let effectiveTier = tier ?? kind.tier

        // The crash countdown is critical: every channel, repeating, never
        // dropped — the watch, audio, and a notification when locked.
        if effectiveTier == .critical {
            var channels: [AlertChannel] = []
            if watch.carriesWatch { channels.append(.watchHaptic) }
            channels.append(contentsOf: audio)
            if locked { channels.append(.localNotification) }
            return Plan(immediate: channels)
        }

        // The watch link announcements are audio-only (the watch can't carry a
        // notice about its own link).
        if kind == .watchDisconnected || kind == .watchReconnected {
            return Plan(immediate: Array(bestAudio.map { [$0] } ?? []))
        }

        switch watch {
        case .ready:
            return readyPlan(for: kind, bestAudio: bestAudio, alsoPlaySound: alsoPlaySound, locked: locked)

        case .degraded, .foregroundOnly:
            // Watch AND audio together: a degraded watch may not buzz, so audio
            // backs every in-ride alert immediately.
            var channels: [AlertChannel] = [.watchHaptic]
            channels.append(contentsOf: audio)
            return Plan(immediate: channels)

        case .unavailable, .unreachable:
            // No watch: fall back to the rear-camera flat routing (audio, or a
            // notification for an important notice when locked; a transient
            // caution is dropped when locked).
            return phoneOnlyPlan(for: kind, audio: audio, locked: locked)
        }
    }

    // MARK: - Private

    /// The plan when the watch is fully `ready`: the watch is primary and audio
    /// is the escalation target (or concurrent when "Also play a sound" is on).
    private static func readyPlan(
        for kind: AlertKind,
        bestAudio: AlertChannel?,
        alsoPlaySound: Bool,
        locked: Bool
    ) -> Plan {
        switch kind {
        case .clipSaved, .clipNotSaved, .cameraResumed:
            // Light confirmations: watch only, no escalation.
            return Plan(immediate: [.watchHaptic])
        default:
            break
        }
        if alsoPlaySound, let bestAudio {
            // Concurrent audio (opt-in); nothing left to escalate to.
            return Plan(immediate: [.watchHaptic, bestAudio])
        }
        // Watch first; escalate to audio on no acknowledgement within the ack
        // timeout. When locked and no audio, a notification backs an important
        // notice.
        let escalation = bestAudio ?? (locked ? .localNotification : nil)
        return Plan(immediate: [.watchHaptic], escalateTo: escalation)
    }

    /// The flat phone-only plan (no watch), mirroring the rear-camera routing
    /// table's "no watch" behavior.
    private static func phoneOnlyPlan(
        for kind: AlertKind,
        audio: [AlertChannel],
        locked: Bool
    ) -> Plan {
        switch kind {
        case .cautionRearVehicle:
            // Transient caution: audio if available, otherwise dropped (never a
            // notification; a stale cue is not worth a lock-screen alert).
            return Plan(immediate: Array(audio.prefix(1)))
        case .cameraInterrupted, .cameraStopped, .phoneBatteryLow:
            // Important notice: audio, else a local notification when locked.
            if let a = audio.first { return Plan(immediate: [a]) }
            return locked ? Plan(immediate: [.localNotification]) : .empty
        case .cameraResumed, .clipSaved, .clipNotSaved:
            // Light confirmation: single audio tick; never a notification.
            return Plan(immediate: Array(audio.prefix(1)))
        default:
            return Plan(immediate: Array(audio.prefix(1)))
        }
    }
}

private extension WatchChannelState {
    /// Whether this channel state can carry a watch haptic at all (reachable and
    /// at least foreground-active).
    var carriesWatch: Bool {
        switch self {
        case .ready, .degraded, .foregroundOnly:
            return true
        case .unavailable, .unreachable:
            return false
        }
    }
}
