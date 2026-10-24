import Foundation
import WhooshWire

/// The keep-alive seam the watch session model uses to start, pause, resume, and
/// end the cycling workout that keeps the watch app running wrist-down
/// (watch-companion spec task 18; design "Keep-alive"; Requirement 4). The real
/// implementation is `HKWorkoutSessionController` (the only HealthKit file on the
/// watch); tests and previews use `FakeWorkoutSessionController`.
///
/// It is **phone-authoritative**: the controller never decides a ride
/// transition. It is driven by the ride state the phone publishes (mapped to the
/// `WorkoutSessionStateMachine` events) and reports its own session phase back as
/// a `WireWatchState` through `onStateChange`, so the phone can tell whether the
/// watch is haptics-ready.
///
/// All methods are main-actor (the watch session model and `HKWorkoutSession`
/// callbacks are main-actor).
@MainActor
protocol WorkoutSessionController: AnyObject {
    /// The current pure session state.
    var state: WorkoutSessionStateMachine.State { get }

    /// The latest reported watch state (session phase, battery, haptics-armed).
    var watchState: WireWatchState { get }

    /// Invoked whenever the reported `WireWatchState` changes so the session
    /// model can send it to the phone.
    var onStateChange: ((WireWatchState) -> Void)? { get set }

    /// The ride became active (phone started a ride, launched the app for a
    /// workout, or the app opened mid-ride). Begins authorization/start.
    func rideBecameActive()

    /// The ride paused / resumed (mapped to the session machine).
    func ridePaused()
    func rideResumed()

    /// The ride finished; moves to the Save/Discard choice.
    func rideFinished()

    /// The rider's end-of-ride choice (or the default-choice timeout).
    func chooseSave()
    func chooseDiscard()

    /// Recover a session left running after a relaunch (orphan/crash recovery).
    func recoverIfNeeded()
}
