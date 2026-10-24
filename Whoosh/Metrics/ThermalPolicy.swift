import Foundation

/// Pure thermal/system-pressure policy for the camera subsystem (rear-camera
/// spec Requirement 12.1, design "ThermalPolicy"). Maps the device thermal level
/// and the capture-session system-pressure level to a **profile step** (or a
/// stop), with step-up hysteresis so the profile never flaps.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). It reads no
/// clock and performs no I/O; `now` and the time of the last change come in via
/// the input so the caller (with a `Clock`) stays deterministic in tests.
///
/// ## Model
/// A capture run has three ordered quality steps, from best to worst:
/// `full` (the requested profile, Standard 30 fps) → `fpsReduced` (frame rate
/// stepped to 24, then 15) → `resolutionReduced` (the Reduced 720p profile,
/// applied only at a segment boundary). The design's "step 1/2/3" maps onto
/// these: step 1 and step 2 are both `fpsReduced` (24 then 15), step 3 is
/// `resolutionReduced`.
///
/// ## Rules (design table)
/// - `nominal`/`fair` ⇒ the requested profile (`full`); consumers at full rate.
/// - `serious` ⇒ step **down** the frame rate first, then resolution at the next
///   boundary; consumers capped at half rate.
/// - `critical` (or a system-pressure shutdown risk) ⇒ **stop** the camera; GPS
///   continues; the rider is told.
/// - Recovery steps **up** one level only after ≥ 5 min at `fair` or better, and
///   at most one step-up per 10 min; never a two-step jump.
enum ThermalPolicy {
    /// The quality step the camera should run at, ordered best → worst.
    enum Step: Int, Equatable, Sendable, CaseIterable, Comparable {
        /// The requested profile at full frame rate.
        case full = 0
        /// Frame rate stepped to 24 fps (first reduction).
        case fps24 = 1
        /// Frame rate stepped to 15 fps (second reduction).
        case fps15 = 2
        /// The Reduced resolution profile (applied at a segment boundary).
        case resolutionReduced = 3

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// What the policy wants the camera to do next.
    enum Decision: Equatable, Sendable {
        /// Run at this quality step.
        case run(Step)
        /// Stop the camera (finalize); GPS continues.
        case stop
    }

    /// The combined pressure the policy reacts to. The higher of thermal level
    /// and system-pressure level drives the decision.
    struct Input: Equatable, Sendable {
        /// The current `ProcessInfo`-mirrored thermal level.
        let thermalLevel: ThermalLevel
        /// The capture-session system-pressure level, mapped to `ThermalLevel`.
        /// A system-pressure shutdown risk arrives as `.critical`.
        let systemPressureLevel: ThermalLevel
        /// The step currently in effect.
        let currentStep: Step
        /// `now`, supplied by the caller's `Clock`.
        let now: Date
        /// When the step last changed (nil if never changed this run).
        let lastChangeAt: Date?
        /// When the last step-**up** (recovery) happened (nil if never).
        let lastStepUpAt: Date?
        /// The tuning values (hysteresis windows).
        let tuning: RideCameraTuning

        init(
            thermalLevel: ThermalLevel,
            systemPressureLevel: ThermalLevel = .nominal,
            currentStep: Step,
            now: Date,
            lastChangeAt: Date? = nil,
            lastStepUpAt: Date? = nil,
            tuning: RideCameraTuning = RideCameraTuning()
        ) {
            self.thermalLevel = thermalLevel
            self.systemPressureLevel = systemPressureLevel
            self.currentStep = currentStep
            self.now = now
            self.lastChangeAt = lastChangeAt
            self.lastStepUpAt = lastStepUpAt
            self.tuning = tuning
        }
    }

    /// Hysteresis defaults (design "RideCameraTuning"): step up only after at
    /// least this long at `fair` or better.
    static let stepUpCooldown: TimeInterval = 5 * 60
    /// …and at most one step-up within this window.
    static let stepUpInterval: TimeInterval = 10 * 60

    /// Whether consumers should be capped at half their declared rate. True at
    /// `serious` (or worse) effective pressure (design: "consumers capped at
    /// half rate at serious").
    static func consumersHalfRate(_ input: Input) -> Bool {
        effectiveLevel(input) >= .serious
    }

    /// Decide the next step or a stop.
    static func decide(_ input: Input) -> Decision {
        let level = effectiveLevel(input)

        switch level {
        case .critical:
            // Critical / system-pressure shutdown risk: stop.
            return .stop

        case .serious:
            // Step down toward the worst step, one step at a time (never jump).
            // At serious we target the resolution-reduced floor but move there
            // step by step across calls; a single call steps down at most one.
            let target = Step.resolutionReduced
            if input.currentStep < target {
                return .run(stepDown(from: input.currentStep))
            }
            return .run(input.currentStep)

        case .nominal, .fair:
            // Recovery: step up at most one level, with hysteresis.
            if input.currentStep == .full {
                return .run(.full)
            }
            if canStepUp(input) {
                return .run(stepUp(from: input.currentStep))
            }
            return .run(input.currentStep)
        }
    }

    // MARK: - Helpers

    /// The pressure that drives the decision: the worse (higher) of thermal and
    /// system-pressure level.
    static func effectiveLevel(_ input: Input) -> ThermalLevel {
        max(input.thermalLevel, input.systemPressureLevel)
    }

    /// One step worse, clamped at the resolution-reduced floor.
    private static func stepDown(from step: Step) -> Step {
        Step(rawValue: min(step.rawValue + 1, Step.resolutionReduced.rawValue)) ?? step
    }

    /// One step better, clamped at `full`.
    private static func stepUp(from step: Step) -> Step {
        Step(rawValue: max(step.rawValue - 1, Step.full.rawValue)) ?? step
    }

    /// Whether the hysteresis windows allow a step-up now: at least
    /// `stepUpCooldown` since the last change AND at least `stepUpInterval`
    /// since the last step-up.
    private static func canStepUp(_ input: Input) -> Bool {
        if let lastChange = input.lastChangeAt {
            if input.now.timeIntervalSince(lastChange) < stepUpCooldown {
                return false
            }
        }
        if let lastUp = input.lastStepUpAt {
            if input.now.timeIntervalSince(lastUp) < stepUpInterval {
                return false
            }
        }
        return true
    }
}
