import Foundation

/// The fan-out `AlertManager` the rest of the app already calls (rear-camera
/// spec task 13, Requirements 13.3–13.5; design "Eyes-free surfaces"). It owns
/// one `AlertSink` per channel and, on `fire(_:)`, asks the pure
/// `AlertRoutingPolicy` which channels to deliver on — given each sink's
/// availability and the current app state — then delivers to the matching sinks
/// in the policy's order.
///
/// The existing `AlertManager` protocol and `StubAlertManager` are unchanged;
/// this is an additive replacement wired at the composition root.
///
/// Guarantees (contract):
/// - **Non-blocking.** `fire(_:)` returns immediately; a sink does its own heavy
///   work off the hot path. Recording is never delayed by alerting.
/// - **Isolated failure.** A sink that is unavailable or throws never stops the
///   other sinks (its error is swallowed; the fan-out logs nothing sensitive).
/// - **Cooldowns.** Per-kind cooldowns are applied by `AlertRoutingPolicy`
///   using the last-delivered times this manager tracks.
///
/// `@MainActor` (project default isolation); the clock and app-state query run
/// on the main actor. The ride hot path hands off to this and returns.
@MainActor
final class FanOutAlertManager: AlertManager {
    private let sinks: [AlertSink]
    private let clock: Clock
    private let tuning: RideCameraTuning
    private let appState: () -> AppAlertState

    /// Last delivery instant keyed by `AlertRoutingPolicy.cooldownKey(_:)`.
    private var lastDeliveredByKind: [String: Date] = [:]

    init(
        sinks: [AlertSink],
        clock: Clock,
        tuning: RideCameraTuning = RideCameraTuning(),
        appState: @escaping () -> AppAlertState
    ) {
        self.sinks = sinks
        self.clock = clock
        self.tuning = tuning
        self.appState = appState
    }

    func fire(_ kind: AlertKind) {
        deliver(kind, ignoringCooldown: false)
    }

    func fireUrgent(_ kind: AlertKind) {
        deliver(kind, ignoringCooldown: true)
    }

    private func deliver(_ kind: AlertKind, ignoringCooldown: Bool) {
        let now = clock.now()
        let state = appState()

        // Available channels right now = channels of sinks that report available.
        let available = Set(sinks.filter { $0.isAvailable }.map { $0.channel })

        let context = AlertRoutingPolicy.Context(
            now: now,
            availableChannels: available,
            appState: state,
            lastDeliveredByKind: ignoringCooldown ? [:] : lastDeliveredByKind
        )
        let channels = AlertRoutingPolicy.route(kind, context: context, tuning: tuning)
        guard !channels.isEmpty else { return }

        let delivery = AlertDeliveryContext(firedAt: now, appState: state)
        var deliveredAny = false
        for channel in channels {
            guard let sink = sinks.first(where: { $0.channel == channel && $0.isAvailable }) else { continue }
            // A sink failure must never affect the others or recording.
            do {
                try sink.deliver(kind, context: delivery)
                deliveredAny = true
            } catch {
                continue
            }
        }

        // Only start the cooldown once something was actually delivered, so a
        // dropped alert does not suppress the next genuine one.
        if deliveredAny {
            lastDeliveredByKind[AlertRoutingPolicy.cooldownKey(kind)] = now
        }
    }
}
