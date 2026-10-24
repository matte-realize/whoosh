import Foundation

/// A named sequence of haptic cues with inter-cue gaps (watch-companion design
/// "Haptic catalog"; Requirement 11.5). A pattern is pure data selected by
/// `HapticPatternSelector`; the watch player walks the steps, playing each
/// `cue` then waiting `gapMs` before the next.
///
/// The platform enforces a ~100 ms minimum between cues; every gap here is at
/// least `WatchTuning.hapticMinCueSpacingMs` (the catalog is authored with
/// gaps ≥ 100 ms and HP-6 asserts it).
public struct HapticPattern: Equatable, Sendable {
    /// One step of a pattern: a cue plus the delay that follows it before the
    /// next cue (the last step's gap is ignored by the player).
    public struct Step: Equatable, Sendable {
        public var cue: HapticCue
        public var gapMs: Int

        public init(cue: HapticCue, gapMs: Int = 0) {
            self.cue = cue
            self.gapMs = gapMs
        }
    }

    /// A short code identifying this pattern (used for the `patternPreview`
    /// alert and diagnostics; never free text).
    public var name: String
    public var steps: [Step]

    public init(name: String, steps: [Step]) {
        self.name = name
        self.steps = steps
    }

    /// The cue sequence, ignoring gaps — the basis of the HP-1 distinctness
    /// "signature".
    public var cues: [HapticCue] { steps.map(\.cue) }

    /// A signature that distinguishes patterns with different *meanings*:
    /// the ordered cue types and the gap profile. Two patterns with the same
    /// signature feel the same on the wrist.
    public var signature: [String] {
        steps.map { "\($0.cue.rawValue):\($0.gapMs)" }
    }
}
