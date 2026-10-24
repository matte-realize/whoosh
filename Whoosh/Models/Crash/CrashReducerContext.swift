import Foundation

/// The ambient context for one reduction step (spec design "Pure functions":
/// "Context carries `now`, deadline, consent/armed flags, per-ride sent count,
/// `suppressedUntil`"). Everything the pure reducer needs that is *not* already
/// in `CrashMachineState` and that it cannot itself produce.
///
/// Foundation-only; `Equatable`, `Sendable`.
/// - `now`: the injected clock instant for this step.
/// - `tuning`: all crash-response constants.
/// - `armed`: the current `CrashArming.isArmed(...)` result (for a new signal).
/// - `online`: whether connectivity is currently satisfied (for dispatch).
/// - `consentCurrent`: whether consent is still current (guards sends).
/// - `newEventId`: a freshly generated id the coordinator supplies, used only
///   when a `detectorSignal` opens a new event (the reducer stays pure).
struct CrashReducerContext: Equatable, Sendable {
    let now: Date
    let tuning: CrashResponseTuning
    let armed: Bool
    let online: Bool
    let consentCurrent: Bool
    let newEventId: UUID

    init(
        now: Date,
        tuning: CrashResponseTuning = CrashResponseTuning(),
        armed: Bool,
        online: Bool,
        consentCurrent: Bool,
        newEventId: UUID
    ) {
        self.now = now
        self.tuning = tuning
        self.armed = armed
        self.online = online
        self.consentCurrent = consentCurrent
        self.newEventId = newEventId
    }
}

/// The result of one reduction: the next state and the ordered effects the
/// coordinator must execute. Foundation-only; `Equatable`, `Sendable`.
struct CrashReduction: Equatable, Sendable {
    let state: CrashMachineState
    let effects: [CrashEffect]

    init(state: CrashMachineState, effects: [CrashEffect]) {
        self.state = state
        self.effects = effects
    }
}
