import Foundation

/// A one-shot alert for the wrist (watch-companion design "`WireAlert`";
/// Requirement 11, 13). Haptic + short text; all values are enums, numbers,
/// booleans, and ids (Requirement 19.1).
///
/// - `level`: 1 or 2 where relevant (rear-vehicle cue level).
/// - `reason`: a camera reason code where relevant.
/// - `value`: a coarse numeric value (for example a battery percent).
/// - `confidence`: coarse 0…10, optional.
/// - `hint`: left/center/right, optional (text only).
/// - `patternName`: a short code naming a catalog pattern for a preview alert.
/// - `outcome`: the crash phase for a `crashCountdownEnded` alert.
/// - `createdAgoMs` / `ttlMs`: skew-free freshness (design time rule L3).
/// - `replay`: a log-only record that must **not** buzz (reconnect fill-in).
public struct WireAlert: Equatable, Codable, Sendable {
    public var alertId: String
    public var kind: WireAlertKind
    public var tier: WireAlertTier
    public var level: Int?
    public var reason: WireCameraReason?
    public var value: Int?
    public var isDemo: Bool
    public var confidence: Int?
    public var hint: WirePositionHint?
    public var patternName: String?
    public var outcome: WireCrashPhase?
    public var createdAgoMs: Int
    public var ttlMs: Int
    public var replay: Bool

    public init(
        alertId: String,
        kind: WireAlertKind,
        tier: WireAlertTier,
        level: Int? = nil,
        reason: WireCameraReason? = nil,
        value: Int? = nil,
        isDemo: Bool = false,
        confidence: Int? = nil,
        hint: WirePositionHint? = nil,
        patternName: String? = nil,
        outcome: WireCrashPhase? = nil,
        createdAgoMs: Int,
        ttlMs: Int,
        replay: Bool = false
    ) {
        self.alertId = alertId
        self.kind = kind
        self.tier = tier
        self.level = level
        self.reason = reason
        self.value = value
        self.isDemo = isDemo
        self.confidence = confidence
        self.hint = hint
        self.patternName = patternName
        self.outcome = outcome
        self.createdAgoMs = createdAgoMs
        self.ttlMs = ttlMs
        self.replay = replay
    }
}
