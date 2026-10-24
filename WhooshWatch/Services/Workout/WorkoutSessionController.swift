import Foundation
import WhooshWire

/// The keep-alive workout seam (watch-companion design "Keep-alive:
/// `WorkoutSessionStateMachine` (pure) and `HKWorkoutSessionController`"). The
/// model drives this protocol in response to ride state; the real implementation
/// (`WhooshWatch/Services/Workout/`) is the only HealthKit code on the watch and
/// owns an `HKWorkoutSession`. Keeping it behind a protocol means the model
/// never imports HealthKit and can be previewed/tested with a fake.
///
/// The controller reports its state back as a `WireWatchState` (session phase,
/// battery, haptics-armed) which the model forwards to the phone.
public protocol WorkoutSessionController: AnyObject, Sendable {
    /// The latest watch state (session phase, battery, flags) to report upstream.
    var watchState: WireWatchState { get }

    /// A ride became active on the phone (or the app opened mid-ride): start (or
    /// recover) the keep-alive session so haptics work with the wrist down.
    func rideBecameActive()

    /// The ride paused — pause the session (per the spike's T11 outcome).
    func ridePaused()

    /// The ride resumed recording.
    func rideResumed()

    /// The ride finished — stop the activity and offer Save/Discard.
    func rideFinished()

    /// The rider chose to keep the workout in Apple Health.
    func saveWorkout()

    /// The rider chose to discard the workout.
    func discardWorkout()

    /// Set a callback the controller invokes whenever its watch state changes
    /// (so the model can forward it to the phone).
    func onWatchStateChange(_ handler: @escaping @Sendable (WireWatchState) -> Void)
}

/// An in-memory `WorkoutSessionController` for previews and tests. Drives the
/// pure `WorkoutSessionStateMachine` so its reported phase is realistic, records
/// the calls it received, and lets a test set the battery and query the machine.
public final class FakeWorkoutSessionController: WorkoutSessionController, @unchecked Sendable {
    private let lock = NSLock()
    private var machine = WorkoutSessionStateMachine()
    private var _watchState: WireWatchState
    private var handler: (@Sendable (WireWatchState) -> Void)?
    public private(set) var calls: [String] = []
    private var authorized: Bool?

    public init(
        authorized: Bool? = true,
        batteryPct: Int = 100
    ) {
        self.authorized = authorized
        self._watchState = WireWatchState(
            session: .none,
            healthAuthorized: authorized,
            appActive: true,
            displayActive: true,
            batteryPct: batteryPct
        )
    }

    public var watchState: WireWatchState {
        lock.lock(); defer { lock.unlock() }
        return _watchState
    }

    public func rideBecameActive() {
        record("rideBecameActive")
        apply(.rideBecameActive(authorized: authorized))
        // The fake fast-forwards authorization/preparation so previews show a
        // running session without real HealthKit.
        if case .authorizing = machineState { apply(.authorizationGranted) }
        if case .preparing = machineState { apply(.sessionRunning) }
    }

    public func ridePaused() { record("ridePaused"); apply(.ridePaused) }
    public func rideResumed() { record("rideResumed"); apply(.rideRecording) }
    public func rideFinished() { record("rideFinished"); apply(.rideFinished) }
    public func saveWorkout() { record("saveWorkout"); apply(.saveChosen) }
    public func discardWorkout() { record("discardWorkout"); apply(.discardChosen) }

    public func onWatchStateChange(_ handler: @escaping @Sendable (WireWatchState) -> Void) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    /// Set the reported battery percentage (previews / tests).
    public func setBattery(_ pct: Int) {
        lock.lock()
        _watchState.batteryPct = max(0, min(100, pct))
        let snapshot = _watchState
        let h = handler
        lock.unlock()
        h?(snapshot)
    }

    private var machineState: WorkoutSessionStateMachine.State {
        machine.state
    }

    private func apply(_ event: WorkoutSessionStateMachine.Event) {
        lock.lock()
        machine.apply(event)
        _watchState.session = Self.phase(for: machine.state)
        _watchState.hapticsArmed = (machine.state == .running)
        if case let .ended(save) = machine.state { _watchState.workoutSaved = save }
        let snapshot = _watchState
        let h = handler
        lock.unlock()
        h?(snapshot)
    }

    private func record(_ name: String) {
        lock.lock(); calls.append(name); lock.unlock()
    }

    private static func phase(for state: WorkoutSessionStateMachine.State) -> WireWorkoutSessionPhase {
        switch state {
        case .off: return .none
        case .authorizing: return .authorizing
        case .preparing: return .preparing
        case .running: return .running
        case .paused: return .paused
        case .stopping: return .stopping
        case .ended: return .none
        case .failed: return .failed
        case .unavailable: return .unavailable
        }
    }
}
