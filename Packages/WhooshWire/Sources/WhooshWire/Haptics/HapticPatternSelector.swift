import Foundation

/// Picks the `HapticPattern` for a `WireAlert` from the catalog table
/// (watch-companion design "Haptic catalog"; Requirement 11.1–11.6, 12.5). Pure
/// and deterministic: given the alert and a little context (the previous rear
/// cue's time, for the level-2 rule) it returns the pattern to play. It never
/// plays navigation cues and never invents a directional meaning from a hint
/// (the hint changes text only, handled by the UI).
///
/// Gaps come from the design catalog; the three safety-critical patterns
/// (crash countdown, rear cue, camera stopped) differ in their first cue or
/// cue count so they are distinguishable on the wrist (HP-1).
public struct HapticPatternSelector: Sendable {
    public init() {}

    /// Context the selector needs that is not on the alert itself.
    public struct Context: Equatable, Sendable {
        /// Milliseconds since the previous rear-vehicle cue was admitted, if any
        /// (drives the level-2 "second cue within 10 s" rule).
        public var msSinceLastRearCue: Int?

        public init(msSinceLastRearCue: Int? = nil) {
            self.msSinceLastRearCue = msSinceLastRearCue
        }

        public static let none = Context()
    }

    /// Window (ms) within which a follow-up rear cue escalates to level 2.
    public static let level2FollowUpWindowMs = 10_000
    /// Confidence (0…10) at or above which a rear cue is level 2 immediately.
    public static let level2ConfidenceThreshold = 8

    /// The pattern for `alert`, or `nil` for a kind that carries no buzz on its
    /// own (e.g. a generic `.unknown` still gets the generic notice).
    public func pattern(for alert: WireAlert, context: Context = .none) -> HapticPattern {
        switch alert.kind {
        case .crashCountdownStarted:
            return Self.crashCountdownStart
        case .crashCountdownEnded:
            // The crash phase decides which end pattern plays.
            switch alert.outcome {
            case .cancelled:
                return Self.crashCancelled
            case .sending, .queuedOffline, .sent:
                return Self.alertSending
            case .failed, .stale:
                return Self.cancelTooLate
            case .countdown, .unknown, .none:
                return Self.alertSending
            }
        case .rearVehicleCaution:
            return Self.rearCue(level: Self.rearLevel(for: alert, context: context))
        case .cameraInterrupted:
            return Self.cameraInterrupted
        case .cameraResumed:
            return Self.cameraResumed
        case .cameraStopped:
            return Self.cameraStopped
        case .clipSaved:
            return Self.clipSaved
        case .clipNotSaved:
            return Self.clipNotSaved
        case .phoneBatteryLow:
            // value ≤ 8 is the critical variant; otherwise the 20% notice.
            if let v = alert.value, v <= 8 {
                return Self.phoneBatteryCritical
            }
            return Self.phoneBatteryLow
        case .linkRestored:
            return Self.linkRestored
        case .patternPreview:
            // A preview names its pattern directly; fall back to notice.
            return Self.previewPattern(named: alert.patternName) ?? Self.genericNotice
        case .hapticTest:
            return Self.hapticTest
        case .unknown:
            return Self.genericNotice
        }
    }

    /// The rear-vehicle level chosen for `alert` given `context`
    /// (design "Selection rules").
    public func rearLevel(for alert: WireAlert, context: Context) -> Int {
        Self.rearLevel(for: alert, context: context)
    }

    static func rearLevel(for alert: WireAlert, context: Context) -> Int {
        if let explicit = alert.level, explicit == 1 || explicit == 2 {
            // An explicit level still escalates on the follow-up rule.
            if explicit == 2 { return 2 }
        }
        if let c = alert.confidence, c >= level2ConfidenceThreshold { return 2 }
        if let since = context.msSinceLastRearCue, since <= level2FollowUpWindowMs { return 2 }
        return 1
    }

    // MARK: - Catalog (design "Haptic catalog" table)

    static let crashCountdownStart = HapticPattern(
        name: "crashCountdownStart",
        steps: [.init(cue: .notification, gapMs: 400),
                .init(cue: .failure, gapMs: 400),
                .init(cue: .failure)]
    )
    static let crashCancelled = HapticPattern(
        name: "crashCancelled",
        steps: [.init(cue: .success)]
    )
    static let cancelTooLate = HapticPattern(
        name: "cancelTooLate",
        steps: [.init(cue: .failure, gapMs: 400), .init(cue: .failure)]
    )
    static let alertSending = HapticPattern(
        name: "alertSending",
        steps: [.init(cue: .stop, gapMs: 300), .init(cue: .stop)]
    )
    static let rearLevel1 = HapticPattern(
        name: "rearLevel1",
        steps: [.init(cue: .directionUp, gapMs: 300), .init(cue: .directionUp)]
    )
    static let rearLevel2 = HapticPattern(
        name: "rearLevel2",
        steps: [.init(cue: .directionUp, gapMs: 250),
                .init(cue: .directionUp, gapMs: 250),
                .init(cue: .directionUp, gapMs: 400),
                .init(cue: .notification)]
    )
    static func rearCue(level: Int) -> HapticPattern {
        level >= 2 ? rearLevel2 : rearLevel1
    }
    static let cameraInterrupted = HapticPattern(
        name: "cameraInterrupted",
        steps: [.init(cue: .retry, gapMs: 400), .init(cue: .retry)]
    )
    static let cameraResumed = HapticPattern(
        name: "cameraResumed",
        steps: [.init(cue: .start)]
    )
    static let cameraStopped = HapticPattern(
        name: "cameraStopped",
        steps: [.init(cue: .failure, gapMs: 500),
                .init(cue: .failure, gapMs: 500),
                .init(cue: .failure)]
    )
    static let clipSaved = HapticPattern(name: "clipSaved", steps: [.init(cue: .success)])
    static let clipNotSaved = HapticPattern(name: "clipNotSaved", steps: [.init(cue: .failure)])
    static let phoneBatteryLow = HapticPattern(
        name: "phoneBatteryLow",
        steps: [.init(cue: .directionDown)]
    )
    static let phoneBatteryCritical = HapticPattern(
        name: "phoneBatteryCritical",
        steps: [.init(cue: .directionDown, gapMs: 350), .init(cue: .directionDown)]
    )
    static let linkLost = HapticPattern(
        name: "linkLost",
        steps: [.init(cue: .retry, gapMs: 600), .init(cue: .directionDown)]
    )
    static let linkRestored = HapticPattern(name: "linkRestored", steps: [.init(cue: .click)])
    static let rideStarted = HapticPattern(name: "rideStarted", steps: [.init(cue: .start)])
    static let rideStopped = HapticPattern(name: "rideStopped", steps: [.init(cue: .stop)])
    static let ridePaused = HapticPattern(name: "ridePaused", steps: [.init(cue: .click)])
    static let commandNotConfirmed = HapticPattern(
        name: "commandNotConfirmed",
        steps: [.init(cue: .failure)]
    )
    static let hapticTest = HapticPattern(
        name: "hapticTest",
        steps: [.init(cue: .notification)]
    )
    static let genericNotice = HapticPattern(
        name: "genericNotice",
        steps: [.init(cue: .notification)]
    )

    /// All catalog patterns with distinct meanings (for the HP-1 distinctness
    /// and HP-6 spacing tests, and the on-watch "Feel patterns" preview list).
    public static let catalog: [HapticPattern] = [
        crashCountdownStart, crashCancelled, cancelTooLate, alertSending,
        rearLevel1, rearLevel2, cameraInterrupted, cameraResumed, cameraStopped,
        clipSaved, clipNotSaved, phoneBatteryLow, phoneBatteryCritical,
        linkLost, linkRestored, rideStarted, rideStopped, ridePaused,
        commandNotConfirmed,
    ]

    /// The three safety-critical patterns that must be unmistakable (HP-1).
    public static let safetyCritical: [HapticPattern] = [
        crashCountdownStart, rearLevel1, cameraStopped,
    ]

    /// Patterns that must feel **distinct from one another** (HP-1). Several
    /// acknowledgements intentionally share a simple cue and are told apart by
    /// context/text, not feel (design "Haptic catalog": `cameraResumed`/
    /// `rideStarted` both `start`; `clipSaved`/`crashCancelled` both `success`;
    /// `clipNotSaved`/`commandNotConfirmed` both `failure`; `linkRestored`/
    /// `ridePaused` both `click`). The distinct-meaning set keeps one
    /// representative of each shared feel so the test asserts a real guarantee.
    public static let distinctMeaningCatalog: [HapticPattern] = [
        crashCountdownStart, crashCancelled, cancelTooLate, alertSending,
        rearLevel1, rearLevel2, cameraInterrupted, cameraStopped,
        clipNotSaved, phoneBatteryLow, phoneBatteryCritical,
        linkLost, rideStarted, ridePaused,
    ]

    static func previewPattern(named name: String?) -> HapticPattern? {
        guard let name else { return nil }
        return catalog.first { $0.name == name }
    }
}
