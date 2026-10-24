import Foundation

/// The per-alert context the fan-out and the watch sink carry alongside an
/// `AlertKind` (watch-companion spec task 9; design "Fan-out, routing, and
/// escalation"; Requirement 12.1, 13.2). Additive: it supplements the existing
/// `AlertDeliveryContext` without changing the `AlertManager`/`AlertSink`
/// protocols.
///
/// It carries the alert's identity (`id`, used for escalation tracking and wire
/// idempotency), its urgency `tier`, a time-to-live (`ttl`), a `demo` flag (a
/// demo-mode alert is labeled DEMO on the watch and honored only while demo mode
/// is active), and the optional detector `confidence` (coarse 0…10) and
/// position `hint` for a rear-vehicle cue. No coordinates, route, footage, or
/// free text ever appear here (Requirement 19.1).
///
/// Foundation-only value type (Models layer); `Equatable`, `Sendable`.
struct AlertContext: Equatable, Sendable {
    /// A stable id for this alert instance (one per fire). Used by the outcome
    /// tracker to escalate at most once and as the wire alert id.
    let id: String
    /// The urgency tier (drives routing and preemption).
    let tier: AlertTier
    /// How long the alert is worth delivering, from `firedAt`. After it expires
    /// the alert is never escalated and the watch never buzzes it.
    let ttl: TimeInterval
    /// Whether this is a demo-mode alert (labeled DEMO on the watch).
    let isDemo: Bool
    /// Optional coarse detector confidence (0…10) for a rear-vehicle cue.
    let confidence: Int?
    /// Optional coarse position hint for a rear-vehicle cue (left/center/right).
    let hint: AlertPositionHint?

    init(
        id: String,
        tier: AlertTier,
        ttl: TimeInterval,
        isDemo: Bool = false,
        confidence: Int? = nil,
        hint: AlertPositionHint? = nil
    ) {
        self.id = id
        self.tier = tier
        self.ttl = ttl
        self.isDemo = isDemo
        self.confidence = confidence
        self.hint = hint
    }
}

/// A coarse rear-vehicle position hint (watch-companion design `WirePositionHint`
/// mirror; Requirement 19.1). Text-only codes, never a bearing or coordinate.
enum AlertPositionHint: String, Equatable, Sendable, CaseIterable {
    case left
    case center
    case right
}
