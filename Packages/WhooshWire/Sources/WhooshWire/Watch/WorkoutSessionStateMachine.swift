import Foundation

/// The pure keep-alive session state machine (watch-companion design
/// "Keep-alive: `WorkoutSessionStateMachine`"; Requirement 4). The real
/// workout-session controller (the only HealthKit file on the watch) drives
/// this machine and performs the effects; the machine itself imports only
/// Foundation and decides the next state from the current state and an event.
///
/// The 19 rows of the design table map to `WS-1…19` tests.
public struct WorkoutSessionStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case off
        case authorizing
        case preparing
        case running
        case paused
        case stopping
        case ended(WireWorkoutSaveState)   // saved | discarded
        case failed(WireSessionReason)
        case unavailable(WireSessionReason)
    }

    public enum Event: Equatable, Sendable {
        /// A ride became active, the phone launched the app for a workout, or
        /// the app opened mid-ride. Carries whether Health is already authorized.
        case rideBecameActive(authorized: Bool?)
        case authorizationGranted
        case authorizationDenied
        case sessionRunning
        case startError
        case startTimeout
        case ridePaused
        case rideRecording
        case rideFinished
        case saveChosen        // or default-save timeout
        case discardChosen     // or default-discard timeout
        case anotherWorkoutStarted
        case systemEndedSession
        case retryTimer(rideActive: Bool, tries: Int)
        case orphanTimeout
        case lowBattery
        case relaunchFoundRecoverableSession
        case nextRideOrSummaryDismissed
    }

    /// Side effects the controller performs (the machine never touches HealthKit).
    public enum Effect: Equatable, Sendable {
        case requestAuthorization
        case createAndStartSession
        case reportWatchState
        case armHaptics
        case retryAfterStartBackoff
        case stopActivityAndShowSummary
        case startHealthChoiceTimer
        case endCollectionAndSave
        case discardCollection
        case endSession
        case emitNotice(WireSessionReason)
        case recoverActiveSession
        case reset
    }

    public struct Outcome: Equatable, Sendable {
        public var state: State
        public var effects: [Effect]
        public init(state: State, effects: [Effect] = []) {
            self.state = state
            self.effects = effects
        }
    }

    public private(set) var state: State

    public init(state: State = .off) {
        self.state = state
    }

    /// Advance the machine. Returns the new state and effects; also mutates
    /// `self.state`. Undefined (state, event) pairs are a no-op (row 19).
    @discardableResult
    public mutating func apply(_ event: Event) -> Outcome {
        let outcome = Self.next(from: state, event: event)
        state = outcome.state
        return outcome
    }

    public static func next(from state: State, event: Event) -> Outcome {
        switch (state, event) {
        // Row 1 / 2: off → authorizing | preparing on the activation triggers.
        case let (.off, .rideBecameActive(authorized)):
            if authorized == true {
                return Outcome(state: .preparing, effects: [.createAndStartSession])
            }
            return Outcome(state: .authorizing, effects: [.requestAuthorization])

        // Row 3: authorizing → preparing when granted.
        case (.authorizing, .authorizationGranted):
            return Outcome(state: .preparing, effects: [.createAndStartSession])

        // Row 4: authorizing → unavailable(healthDenied) when denied.
        case (.authorizing, .authorizationDenied):
            return Outcome(state: .unavailable(.healthDenied),
                           effects: [.reportWatchState])

        // Row 5: preparing → running when the session is running.
        case (.preparing, .sessionRunning):
            return Outcome(state: .running, effects: [.reportWatchState, .armHaptics])

        // Row 6: preparing → failed(startFailed) on error or 10 s timeout.
        case (.preparing, .startError), (.preparing, .startTimeout):
            return Outcome(state: .failed(.startFailed),
                           effects: [.reportWatchState, .retryAfterStartBackoff])

        // Row 7: running → paused on ride paused.
        case (.running, .ridePaused):
            return Outcome(state: .paused, effects: [])

        // Row 8: paused → running on ride recording.
        case (.paused, .rideRecording):
            return Outcome(state: .running, effects: [])

        // Row 9: running | paused → stopping on ride finished / idle.
        case (.running, .rideFinished), (.paused, .rideFinished):
            return Outcome(state: .stopping,
                           effects: [.stopActivityAndShowSummary, .startHealthChoiceTimer])

        // Row 10: stopping → ended(saved) on Save (or default-save timeout).
        case (.stopping, .saveChosen):
            return Outcome(state: .ended(.saved),
                           effects: [.endCollectionAndSave, .endSession])

        // Row 11: stopping → ended(discarded) on Discard (or default-discard).
        case (.stopping, .discardChosen):
            return Outcome(state: .ended(.discarded),
                           effects: [.discardCollection, .endSession])

        // Row 12: running | paused → failed(anotherWorkout).
        case (.running, .anotherWorkoutStarted), (.paused, .anotherWorkoutStarted):
            return Outcome(state: .failed(.anotherWorkout),
                           effects: [.reportWatchState, .emitNotice(.anotherWorkout)])

        // Row 13: failed(startFailed|systemEnded) → preparing on retry while the
        // ride is active and tries < 2.
        case let (.failed(reason), .retryTimer(rideActive, tries)):
            if (reason == .startFailed || reason == .systemEnded), rideActive, tries < 2 {
                return Outcome(state: .preparing,
                               effects: [.retryAfterStartBackoff, .createAndStartSession])
            }
            return Outcome(state: .failed(reason))

        // Row 14: running | paused → failed(systemEnded) when the system ends it.
        case (.running, .systemEndedSession), (.paused, .systemEndedSession):
            return Outcome(state: .failed(.systemEnded),
                           effects: [.reportWatchState, .retryAfterStartBackoff])

        // Row 15: running | paused → stopping on the orphan timeout.
        case (.running, .orphanTimeout), (.paused, .orphanTimeout):
            return Outcome(state: .stopping,
                           effects: [.emitNotice(.orphanTimeout), .stopActivityAndShowSummary,
                                     .startHealthChoiceTimer])

        // Row 16: running | paused → stopping at ≤ 5% battery.
        case (.running, .lowBattery), (.paused, .lowBattery):
            return Outcome(state: .stopping,
                           effects: [.emitNotice(.lowBattery), .stopActivityAndShowSummary,
                                     .startHealthChoiceTimer])

        // Row 17: off → preparing when a relaunch finds a recoverable session.
        case (.off, .relaunchFoundRecoverableSession):
            return Outcome(state: .preparing, effects: [.recoverActiveSession])

        // Row 18: ended → off on the next ride or summary dismissed.
        case (.ended, .nextRideOrSummaryDismissed):
            return Outcome(state: .off, effects: [.reset])

        // Row 19: any other (state, event) → no-op.
        default:
            return Outcome(state: state)
        }
    }
}
