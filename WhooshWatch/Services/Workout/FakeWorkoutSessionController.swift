import Foundation
import WhooshWire

/// A scriptable `WorkoutSessionController` for tests and previews (watch-companion
/// spec task 18). It drives the pure `WorkoutSessionStateMachine` with no
/// HealthKit, so the session-model wiring can be exercised off-device, and
/// records the phases it reported.
///
/// It auto-advances the two async machine steps that the real controller gets
/// from HealthKit callbacks — authorization (assumed granted) and session start
/// — so a simple `rideBecameActive()` drives through to `running` in a test.
@MainActor
final class FakeWorkoutSessionController: WorkoutSessionController {
    private var machine = WorkoutSessionStateMachine()

    /// Whether Health share authorization is (pretended) granted.
    var authorized: Bool
    /// Whether a created session reaches `running` (false simulates a start
    /// failure so the retry path can be tested).
    var sessionStartsSuccessfully: Bool

    /// Every `WireWatchState` reported, in order.
    private(set) var reported: [WireWatchState] = []

    var state: WorkoutSessionStateMachine.State { machine.state }
    private(set) var watchState: WireWatchState
    var onStateChange: ((WireWatchState) -> Void)?

    init(authorized: Bool = true, sessionStartsSuccessfully: Bool = true) {
        self.authorized = authorized
        self.sessionStartsSuccessfully = sessionStartsSuccessfully
        self.watchState = WireWatchState(
            session: .none,
            appActive: true,
            displayActive: true,
            batteryPct: 100
        )
    }

    func rideBecameActive() {
        apply(.rideBecameActive(authorized: authorized))
        if case .authorizing = machine.state {
            apply(authorized ? .authorizationGranted : .authorizationDenied)
        }
        if case .preparing = machine.state {
            apply(sessionStartsSuccessfully ? .sessionRunning : .startError)
        }
    }

    func ridePaused() { apply(.ridePaused) }
    func rideResumed() { apply(.rideRecording) }
    func rideFinished() { apply(.rideFinished) }
    func chooseSave() { apply(.saveChosen) }
    func chooseDiscard() { apply(.discardChosen) }
    func recoverIfNeeded() { apply(.relaunchFoundRecoverableSession) }

    private func apply(_ event: WorkoutSessionStateMachine.Event) {
        machine.apply(event)
        let phase: WireWorkoutSessionPhase
        switch machine.state {
        case .off, .ended: phase = .none
        case .authorizing: phase = .authorizing
        case .preparing: phase = .preparing
        case .running: phase = .running
        case .paused: phase = .paused
        case .stopping: phase = .stopping
        case .failed: phase = .failed
        case .unavailable: phase = .unavailable
        }
        let newState = WireWatchState(
            session: phase,
            appActive: true,
            displayActive: true,
            batteryPct: 100,
            hapticsArmed: phase == .running
        )
        watchState = newState
        reported.append(newState)
        onStateChange?(newState)
    }
}
