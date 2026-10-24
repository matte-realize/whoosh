import Foundation

/// The urgency tier of an alert on the phone side (watch-companion spec task 9;
/// design "Fan-out, routing, and escalation"; Requirement 12.1, 13.2). Mirrors
/// the wire `WireAlertTier` so the phone can reason about preemption and
/// escalation without importing the wire type everywhere.
///
/// A higher tier preempts a lower one and is routed more aggressively (the crash
/// countdown is `critical` and goes to every channel). Ordered by urgency:
/// `critical > caution > notice > confirm`.
///
/// Foundation-only enum (Models layer); `Equatable`, `Hashable`, `Sendable`,
/// `CaseIterable`, `Comparable` (by urgency).
enum AlertTier: String, Equatable, Hashable, Sendable, CaseIterable, Comparable {
    /// The crash countdown: delivered on every channel, repeating, never dropped.
    case critical
    /// A cautionary cue (rear-vehicle, camera stopped, battery critical).
    case caution
    /// An informational notice (camera interrupted/resumed, battery low, links).
    case notice
    /// A light confirmation (clip saved, cancel confirmed).
    case confirm

    /// Rank for comparison: higher rank = more urgent.
    private var rank: Int {
        switch self {
        case .critical: return 3
        case .caution: return 2
        case .notice: return 1
        case .confirm: return 0
        }
    }

    static func < (lhs: AlertTier, rhs: AlertTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

extension AlertKind {
    /// The urgency tier of this alert kind (watch-companion design haptic
    /// catalog: tier column). Drives routing and escalation decisions.
    var tier: AlertTier {
        switch self {
        case .cautionRearVehicle:
            return .caution
        case .cameraStopped:
            return .caution
        case .cameraInterrupted:
            return .notice
        case .cameraResumed:
            return .confirm
        case .clipSaved:
            return .confirm
        case .clipNotSaved:
            return .notice
        case .phoneBatteryLow:
            return .notice
        case .watchDisconnected, .watchReconnected:
            return .notice
        }
    }
}
