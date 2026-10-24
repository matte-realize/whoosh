import Foundation

/// Pure policy that routes an `AlertKind` to an **ordered** list of
/// `AlertChannel`s, given the available channels, the app's visibility state,
/// and per-kind cooldowns (rear-camera spec task 10, Requirements 13.3, 13.4;
/// design "Eyes-free surfaces: Routing table").
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The
/// `FanOutAlertManager` delivers to the sinks whose channel appears in the
/// returned list, in order; it never blocks recording and a failed sink never
/// affects the others.
///
/// Routing principles (from the design table):
/// - Watch haptic is preferred first for every in-ride alert.
/// - Rear-vehicle caution is a transient cue: it uses exactly one channel
///   (watch → headphones → speaker) and is **dropped** (stale) when the phone
///   is locked/backgrounded with no watch.
/// - Camera notices (interrupted/stopped) are important: they use every
///   available in-ride channel, and fall back to a local notification when
///   locked/backgrounded.
/// - Light confirmations (clipSaved/clipNotSaved/cameraResumed) use a single
///   best channel and never a local notification.
/// - Per-kind cooldowns: rear-vehicle at most once per `rearVehicleAlertCooldown`
///   (3 s); camera notices at most once per `cameraNoticeCooldown` (60 s) **per
///   reason** (the cooldown key includes the stop reason).
enum AlertRoutingPolicy {

    /// The non-kind inputs the routing needs.
    struct Context: Equatable, Sendable {
        /// The instant the alert is being routed.
        var now: Date
        /// Channels currently available (watch reachable, audio route, etc.).
        var availableChannels: Set<AlertChannel>
        /// The app's foreground/visibility state.
        var appState: AppAlertState
        /// Last delivery instant keyed by `cooldownKey(_:)`.
        var lastDeliveredByKind: [String: Date]

        init(
            now: Date,
            availableChannels: Set<AlertChannel>,
            appState: AppAlertState,
            lastDeliveredByKind: [String: Date]
        ) {
            self.now = now
            self.availableChannels = availableChannels
            self.appState = appState
            self.lastDeliveredByKind = lastDeliveredByKind
        }
    }

    /// A stable cooldown key for an alert kind. Camera stops include the reason
    /// so distinct reasons cool down independently; other kinds use a bare name.
    static func cooldownKey(_ kind: AlertKind) -> String {
        switch kind {
        case .cautionRearVehicle: return "cautionRearVehicle"
        case .cameraInterrupted: return "cameraInterrupted"
        case .cameraResumed: return "cameraResumed"
        case let .cameraStopped(reason): return "cameraStopped.\(reason.rawValue)"
        case .clipSaved: return "clipSaved"
        case let .clipNotSaved(reason): return "clipNotSaved.\(reason.rawValue)"
        case .phoneBatteryLow: return "phoneBatteryLow"
        case .watchDisconnected: return "watchDisconnected"
        case .watchReconnected: return "watchReconnected"
        }
    }

    /// Route `kind` to an ordered list of channels. Empty means "dropped".
    static func route(
        _ kind: AlertKind,
        context: Context,
        tuning: RideCameraTuning
    ) -> [AlertChannel] {
        // Cooldown gate first: a kind within its cooldown is dropped.
        if let last = context.lastDeliveredByKind[cooldownKey(kind)] {
            let elapsed = context.now.timeIntervalSince(last)
            if elapsed < cooldown(for: kind, tuning: tuning) { return [] }
        }

        let candidates = orderedCandidates(for: kind, appState: context.appState)
        let routed = candidates.filter { context.availableChannels.contains($0) }

        // Transient cues and light confirmations take a single best channel.
        if usesSingleChannel(kind) {
            return Array(routed.prefix(1))
        }
        return routed
    }

    // MARK: - Private

    /// Per-kind cooldown length.
    private static func cooldown(for kind: AlertKind, tuning: RideCameraTuning) -> TimeInterval {
        switch kind {
        case .cautionRearVehicle:
            return tuning.rearVehicleAlertCooldown
        case .cameraInterrupted, .cameraResumed, .cameraStopped, .phoneBatteryLow:
            return tuning.cameraNoticeCooldown
        case .clipSaved, .clipNotSaved:
            return 0
        case .watchDisconnected, .watchReconnected:
            // Link-state announcements are coalesced with the camera-notice
            // cooldown so a flapping link does not spam the rider.
            return tuning.cameraNoticeCooldown
        }
    }

    /// Whether the kind delivers on a single best channel (true) or fans out to
    /// every available in-ride channel (false).
    private static func usesSingleChannel(_ kind: AlertKind) -> Bool {
        switch kind {
        case .cautionRearVehicle, .cameraResumed, .clipSaved, .clipNotSaved:
            return true
        case .cameraInterrupted, .cameraStopped, .phoneBatteryLow:
            return false
        case .watchDisconnected, .watchReconnected:
            // A single audio announcement; never fans out to the watch (it is
            // the watch link that is being announced).
            return true
        }
    }

    /// The channels to consider for a kind, in preference order, for the given
    /// app state. Membership is intersected with availability by the caller.
    private static func orderedCandidates(
        for kind: AlertKind,
        appState: AppAlertState
    ) -> [AlertChannel] {
        let locked = (appState == .lockedOrBackgrounded)
        switch kind {
        case .cautionRearVehicle:
            // A transient caution is dropped when locked (stale); otherwise
            // watch → headphones → speaker.
            return locked ? [.watchHaptic] : [.watchHaptic, .phoneHeadphones, .phoneSpeaker]
        case .cameraInterrupted, .cameraStopped:
            // Important notice: all in-ride channels; local notification when locked.
            return locked
                ? [.watchHaptic, .localNotification]
                : [.watchHaptic, .phoneHeadphones, .phoneSpeaker]
        case .phoneBatteryLow:
            return locked
                ? [.watchHaptic, .localNotification]
                : [.watchHaptic, .phoneHeadphones, .phoneSpeaker]
        case .cameraResumed:
            return [.watchHaptic, .phoneHeadphones, .phoneSpeaker]
        case .clipSaved, .clipNotSaved:
            // Light confirmation: watch → audio; never a local notification.
            return [.watchHaptic, .phoneHeadphones, .phoneSpeaker]
        case .watchDisconnected, .watchReconnected:
            // Audio only, on every watch-channel column (the watch link itself
            // is what is being announced, so it can never carry this). No local
            // notification: it is a transient spoken notice.
            return [.phoneHeadphones, .phoneSpeaker]
        }
    }
}
