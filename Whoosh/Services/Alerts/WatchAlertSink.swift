import Foundation
import WhooshWire

/// The Apple Watch `AlertSink`: it delivers an alert to the wrist over a
/// `WireLink` and escalates to phone audio when the watch does not acknowledge
/// (watch-companion spec task 14; design "Fan-out, routing, and escalation";
/// Requirement 13.1–13.7, 1.4). It is the watch-channel member of the
/// `FanOutAlertManager`'s sinks, alongside the existing phone audio,
/// notification, and phone-haptic sinks; the `AlertManager` protocol is
/// unchanged.
///
/// ## Delivery
/// `deliver(_:context:)` returns immediately (never blocks recording). It
/// synthesizes an allowlisted `WireAlert` (enums, numbers, booleans, ids only —
/// no coordinates, footage, or free text), begins tracking the alert in the pure
/// `AlertOutcomeTracker`, schedules the acknowledgement timeout on the `Clock`,
/// and fires the live send in a detached `Task`. When the watch replies with a
/// `WireAlertReceipt`, a `played` result **confirms** the cue (no escalation); a
/// suppressed/failed result or no reply within the timeout **escalates once** to
/// audio through the injected `escalate` closure (unless "Also play a sound" is
/// on, in which case audio already played concurrently). A stale alert past its
/// TTL never escalates.
///
/// ## Isolation and failure
/// `@MainActor` to match the `FanOutAlertManager` that drives it. A send failure
/// or an unreachable link leaves the other sinks and ride recording untouched
/// (the error is swallowed; the escalation path still runs). The watch itself
/// decides whether to buzz (freshness + limiter on the watch side); this sink
/// only sends and records the outcome.
@MainActor
final class WatchAlertSink: AlertSink {
    let channel: AlertChannel = .watchHaptic

    /// The sink is available while the link reports reachable.
    var isAvailable: Bool { isReachable() }

    private let link: WireLink
    private let clock: Clock
    private let tuning: WatchTuning
    private let isReachable: () -> Bool
    /// Fallback when the watch does not acknowledge in time (the audio sink).
    private let escalate: (AlertKind, AlertDeliveryContext) -> Void
    /// "Also play a sound" (O-W7): when on, audio accompanies the watch cue
    /// concurrently, so a timeout does not additionally escalate.
    private let alsoPlaySound: () -> Bool
    /// Supplies a fresh alert id per delivery (overridable in tests).
    private let makeAlertId: () -> String

    /// The escalation/outcome ledger (pure). Exposed for tests.
    private(set) var outcomes = AlertOutcomeTracker()
    /// The last receipt result observed, for diagnostics/tests.
    private(set) var lastReceipt: WireAlertReceiptResult?

    init(
        link: WireLink,
        clock: Clock,
        tuning: WatchTuning = WatchTuning(),
        isReachable: @escaping () -> Bool,
        escalate: @escaping (AlertKind, AlertDeliveryContext) -> Void,
        alsoPlaySound: @escaping () -> Bool = { false },
        makeAlertId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.link = link
        self.clock = clock
        self.tuning = tuning
        self.isReachable = isReachable
        self.escalate = escalate
        self.alsoPlaySound = alsoPlaySound
        self.makeAlertId = makeAlertId
    }

    // MARK: - AlertSink

    func deliver(_ kind: AlertKind, context: AlertDeliveryContext) throws {
        deliver(kind, context: context, overrideContext: nil)
    }

    /// Deliver with an optional richer `AlertContext` (id, tier, ttl, demo). The
    /// fan-out that knows the context passes it here; the plain `AlertSink`
    /// entry point synthesizes one from the kind.
    func deliver(_ kind: AlertKind, context: AlertDeliveryContext, overrideContext: AlertContext?) {
        let (alert, alertId) = prepare(kind, context: context, overrideContext: overrideContext)
        guard let alert else {
            handleReceipt(alertId: alertId, result: .failed, kind: kind, context: context)
            return
        }
        let link = self.link
        Task { [weak self] in
            let result = await link.send(alert.envelope)
            self?.handleSendResult(result, alertId: alertId, kind: kind, context: context)
        }
    }

    /// Test seam: perform the full delivery and await the send + receipt
    /// deterministically (production uses the fire-and-forget `deliver`).
    func deliverAwaitingSend(_ kind: AlertKind, context: AlertDeliveryContext, overrideContext: AlertContext? = nil) async {
        let (alert, alertId) = prepare(kind, context: context, overrideContext: overrideContext)
        guard let alert else {
            handleReceipt(alertId: alertId, result: .failed, kind: kind, context: context)
            return
        }
        let result = await link.send(alert.envelope)
        handleSendResult(result, alertId: alertId, kind: kind, context: context)
    }

    /// An encoded alert plus its id (nil envelope means an encode failure).
    private struct PreparedAlert { let envelope: WireEnvelope }

    /// Synthesize the wire alert, start outcome tracking, and schedule the
    /// acknowledgement timeout. Returns the encoded alert (or nil on encode
    /// failure) and its id.
    private func prepare(
        _ kind: AlertKind,
        context: AlertDeliveryContext,
        overrideContext: AlertContext?
    ) -> (PreparedAlert?, String) {
        let now = clock.now()
        let alertId = overrideContext?.id ?? makeAlertId()
        let tier = overrideContext?.tier ?? kind.tier
        let ttlMs = overrideContext.map { Int($0.ttl * 1000) } ?? defaultTtlMs(for: kind)

        let alert = WireAlert(
            alertId: alertId,
            kind: Self.wireKind(kind),
            tier: Self.wireTier(tier),
            level: nil,
            reason: Self.wireReason(kind),
            value: nil,
            isDemo: overrideContext?.isDemo ?? false,
            confidence: overrideContext?.confidence,
            hint: overrideContext.flatMap { Self.wireHint($0.hint) },
            createdAgoMs: 0,
            ttlMs: ttlMs
        )

        outcomes.track(id: alertId, firedAt: now, ttl: TimeInterval(ttlMs) / 1000)
        if !alsoPlaySound() {
            clock.schedule(after: TimeInterval(tuning.watchAckTimeoutMs) / 1000) { [weak self] in
                self?.onAckTimeout(alertId: alertId, kind: kind, context: context)
            }
        }

        guard let envelope = try? WireCodec.encode(
            alert, id: alertId, seq: 0, sentAt: now.timeIntervalSince1970, ttlMs: ttlMs
        ) else {
            return (nil, alertId)
        }
        return (PreparedAlert(envelope: envelope), alertId)
    }

    // MARK: - Outcome handling

    /// Map the live send result to a receipt outcome on the main actor.
    private func handleSendResult(
        _ result: WireSendResult,
        alertId: String,
        kind: AlertKind,
        context: AlertDeliveryContext
    ) {
        switch result {
        case let .delivered(reply):
            if let reply, let receipt = try? WireCodec.decodePayload(WireAlertReceipt.self, from: reply) {
                handleReceipt(alertId: alertId, result: receipt.result, kind: kind, context: context)
            } else {
                // Delivered but no receipt: treat as unconfirmed; the timeout
                // will escalate if still fresh.
                lastReceipt = nil
            }
        case .queued:
            // Stored for later (not a live buzz): the watch logs it on reconnect
            // (a replay record) but it never buzzes; no escalation here.
            lastReceipt = nil
        case .unreachable, .failed:
            handleReceipt(alertId: alertId, result: .failed, kind: kind, context: context)
        }
    }

    /// Apply a receipt: `played` confirms; anything else escalates once (if the
    /// alert is still pending and fresh).
    private func handleReceipt(
        alertId: String,
        result: WireAlertReceiptResult,
        kind: AlertKind,
        context: AlertDeliveryContext
    ) {
        lastReceipt = result
        switch result {
        case .played:
            outcomes.confirm(id: alertId)
        case .suppressedDemo, .suppressedDisabled, .suppressedDuplicate,
             .suppressedHigherTier, .suppressedRate, .suppressedStale,
             .suppressedNotActive, .failed, .unknown:
            escalateIfNeeded(alertId: alertId, kind: kind, context: context)
        }
    }

    /// The acknowledgement timeout fired: escalate if the watch never confirmed.
    private func onAckTimeout(alertId: String, kind: AlertKind, context: AlertDeliveryContext) {
        escalateIfNeeded(alertId: alertId, kind: kind, context: context)
    }

    /// Escalate to audio exactly once, within TTL, and only when still pending.
    private func escalateIfNeeded(alertId: String, kind: AlertKind, context: AlertDeliveryContext) {
        let now = clock.now()
        if outcomes.escalateOnTimeout(id: alertId, now: now) == .escalate {
            escalate(kind, context)
        }
    }

    // MARK: - Mapping (allowlist boundary)

    private func defaultTtlMs(for kind: AlertKind) -> Int {
        switch kind {
        case .cautionRearVehicle: return tuning.ttlRearVehicleMs
        case .clipSaved, .clipNotSaved: return tuning.ttlClipNoticeMs
        case .cameraInterrupted, .cameraResumed, .cameraStopped, .phoneBatteryLow:
            return tuning.ttlCameraBatteryMs
        case .watchDisconnected, .watchReconnected:
            return tuning.ttlLinkNoticeMs
        }
    }

    static func wireKind(_ kind: AlertKind) -> WireAlertKind {
        switch kind {
        case .cautionRearVehicle: return .rearVehicleCaution
        case .cameraInterrupted: return .cameraInterrupted
        case .cameraResumed: return .cameraResumed
        case .cameraStopped: return .cameraStopped
        case .clipSaved: return .clipSaved
        case .clipNotSaved: return .clipNotSaved
        case .phoneBatteryLow: return .phoneBatteryLow
        case .watchReconnected: return .linkRestored
        case .watchDisconnected: return .unknown   // announced on audio, not the watch
        }
    }

    static func wireTier(_ tier: AlertTier) -> WireAlertTier {
        switch tier {
        case .critical: return .critical
        case .caution: return .caution
        case .notice: return .notice
        case .confirm: return .confirm
        }
    }

    /// The camera reason code carried for camera-stop alerts (no free text).
    static func wireReason(_ kind: AlertKind) -> WireCameraReason? {
        switch kind {
        case let .cameraStopped(reason):
            switch reason {
            case .thermal: return .thermal
            case .storage: return .storage
            case .battery: return .battery
            case .permission: return .permission
            case .failed: return .failed
            case .rideEnded: return nil
            }
        case .cameraInterrupted: return .interrupted
        default: return nil
        }
    }

    static func wireHint(_ hint: AlertPositionHint?) -> WirePositionHint? {
        switch hint {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case nil: return nil
        }
    }
}
