import Foundation

/// One output channel for alerts (rear-camera spec Requirement 13.3, design
/// "Eyes-free surfaces"). The `FanOutAlertManager` owns one sink per
/// `AlertChannel` and, driven by the pure `AlertRoutingPolicy`, delivers an
/// alert to the sinks whose channel was selected.
///
/// ## Contract
/// - **One channel.** Each sink reports its `channel`; the policy routes by it.
/// - **Non-blocking.** `deliver(_:context:)` MUST return immediately and MUST
///   never block, slow, or stop ride recording. Heavy haptic/audio work is the
///   implementation's own concern, kept off the hot path.
/// - **Isolated failure.** A sink that is unavailable or fails MUST NOT affect
///   other sinks or recording; it signals unavailability via `isAvailable` and
///   throws from `deliver` only to report its own local failure.
/// - **On-device.** Sinks never touch the network.
protocol AlertSink: AnyObject {
    /// The single channel this sink delivers on.
    var channel: AlertChannel { get }
    /// Whether the sink can deliver right now (watch reachable, audio route up).
    var isAvailable: Bool { get }
    /// Deliver an alert. Returns immediately; throws only to report a local
    /// failure the fan-out will swallow (never propagated to recording).
    func deliver(_ kind: AlertKind, context: AlertDeliveryContext) throws
}

/// Context passed to a sink with an alert (rear-camera spec design). Carries the
/// delivery instant and the app state so a sink can tailor its presentation; it
/// never carries footage or clip references.
struct AlertDeliveryContext: Equatable, Sendable {
    /// When the alert fired.
    let firedAt: Date
    /// The app's foreground/visibility state at fire time.
    let appState: AppAlertState

    init(firedAt: Date, appState: AppAlertState) {
        self.firedAt = firedAt
        self.appState = appState
    }
}
