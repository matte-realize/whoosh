import Foundation
import HealthKit
import WhooshWire
#if os(watchOS)
import WatchKit
#endif

/// The watch's keep-alive workout controller (watch-companion spec task 18;
/// design "Keep-alive: `WorkoutSessionStateMachine` (pure) and
/// `HKWorkoutSessionController`"; Requirement 4.1–4.12, 16.2, 16.3, 16.6, 19.5).
///
/// This is the **only** HealthKit file on the watch (enforced by
/// `scripts/privacy-check.sh` rule 20). It:
/// - requests **share-only** authorization for the cycling workout type and
///   **reads nothing** (write-only Health; Requirement 19.5);
/// - creates and runs an `HKWorkoutSession` + `HKLiveWorkoutBuilder` so the app
///   keeps running and may play haptics with the wrist down;
/// - maps ride state (from the phone) and session/system events onto the pure
///   `WorkoutSessionStateMachine`, then performs the machine's effects;
/// - reports a `WireWatchState` (session phase, haptics-armed, battery, …) on
///   every change so the phone's channel evaluator knows whether the watch is
///   haptics-ready.
///
/// It keeps CPU minimal: no per-second work (the elapsed clock is ticked from an
/// anchor in the pure projector), only event-driven transitions.
///
/// _Pending task 1 spike:_ the on-device feasibility spike (tasks.md task 1) has
/// not been run. O-W2 (this cycling keep-alive) is the owner-approved path and
/// the fallback-ladder rung F0 the design assumes. Two rows are explicitly
/// gated on the spike's measured behaviour and left conservative here:
/// - **T11 (paused session):** the machine pauses the session on a ride pause
///   (row 7). If the spike shows a paused session is suspended (haptics blocked),
///   switch to keeping it running — change only the effect mapping, not this file's
///   structure. Noted at `ridePaused()`.
/// - **O-W4 (location type):** `.outdoor` is used (GPS indicator on, matches a
///   real outdoor ride). If the spike's T12 shows a battery/background problem,
///   switch to `.unknown`. Noted at `makeConfiguration()`.
@MainActor
final class HKWorkoutSessionController: NSObject, WorkoutSessionController {

    // MARK: State

    private var machine = WorkoutSessionStateMachine()
    private var startTries = 0

    var state: WorkoutSessionStateMachine.State { machine.state }

    private(set) var watchState: WireWatchState
    var onStateChange: ((WireWatchState) -> Void)?

    // MARK: HealthKit

    private let healthStore: HKHealthStore?
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    override init() {
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        self.watchState = Self.initialWatchState(available: HKHealthStore.isHealthDataAvailable())
        super.init()
    }

    // MARK: - WorkoutSessionController

    func rideBecameActive() {
        guard healthStore != nil else {
            // No Health on this device: report unavailable; phone falls back to
            // audio-only (the ride is never blocked).
            apply(.rideBecameActive(authorized: false))
            return
        }
        let authorized = isWorkoutShareAuthorized()
        apply(.rideBecameActive(authorized: authorized))
    }

    func ridePaused() {
        // _Pending task 1 spike (T11)._ Pausing the session mirrors the ride; if
        // the spike shows a paused session suspends haptics, keep it running and
        // only record a pause instead (change the effect, not this call).
        apply(.ridePaused)
    }

    func rideResumed() { apply(.rideRecording) }

    func rideFinished() { apply(.rideFinished) }

    func chooseSave() { apply(.saveChosen) }

    func chooseDiscard() { apply(.discardChosen) }

    func recoverIfNeeded() {
        guard healthStore != nil else { return }
        // The state machine only recovers from `off`; if a session is already
        // live this is a no-op (row 19).
        apply(.relaunchFoundRecoverableSession)
    }

    // MARK: - Machine driving

    /// Apply an event to the pure machine and perform the returned effects.
    private func apply(_ event: WorkoutSessionStateMachine.Event) {
        let outcome = machine.apply(event)
        for effect in outcome.effects {
            perform(effect)
        }
        // Keep the reported phase in sync with the machine after every event.
        refreshWatchState()
    }

    private func perform(_ effect: WorkoutSessionStateMachine.Effect) {
        switch effect {
        case .requestAuthorization:
            requestShareOnlyAuthorization()
        case .createAndStartSession:
            startTries += 1
            createAndStartSession()
        case .reportWatchState:
            refreshWatchState()
        case .armHaptics:
            // Haptics are considered armed while the session runs; the flag is
            // reflected in the reported WireWatchState.
            refreshWatchState()
        case .retryAfterStartBackoff:
            scheduleStartRetry()
        case .stopActivityAndShowSummary:
            session?.stopActivity(with: Date())
        case .startHealthChoiceTimer:
            scheduleDefaultChoice()
        case .endCollectionAndSave:
            endCollectionAndSave()
        case .discardCollection:
            discardCollection()
        case .endSession:
            session?.end()
        case .emitNotice:
            // Notices surface on the watch session model / phone; nothing to do
            // in HealthKit beyond the state report already made.
            break
        case .recoverActiveSession:
            recoverActiveSession()
        case .reset:
            resetSession()
        }
    }

    // MARK: - HealthKit effects

    private func requestShareOnlyAuthorization() {
        guard let healthStore else { apply(.authorizationDenied); return }
        let cyclingType = HKObjectType.workoutType()
        // Share-only: the write set carries the workout type; the read set is
        // empty (Requirement 19.5 — Whoosh reads no Health data).
        healthStore.requestAuthorization(toShare: [cyclingType], read: []) { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(granted ? .authorizationGranted : .authorizationDenied)
            }
        }
    }

    private func createAndStartSession() {
        guard let healthStore else { apply(.startError); return }
        let configuration = makeConfiguration()
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] success, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !success { self.apply(.startError) }
                    // Running is reported via the session delegate's state change.
                }
            }
        } catch {
            apply(.startError)
        }
    }

    private func makeConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        // _O-W4:_ `.outdoor` matches a real outdoor ride (GPS indicator on). The
        // spike's T12 may switch this to `.unknown` for battery/background
        // reasons; change only this value.
        configuration.locationType = .outdoor
        return configuration
    }

    private func endCollectionAndSave() {
        guard let builder else { return }
        let end = Date()
        builder.endCollection(withEnd: end) { [weak builder] _, _ in
            builder?.finishWorkout { _, _ in }
        }
    }

    private func discardCollection() {
        // Discarding means not finishing the builder: end the session without a
        // finishWorkout call, so nothing is written to Health.
        session?.end()
    }

    private func recoverActiveSession() {
        guard let healthStore else { return }
        healthStore.recoverActiveWorkoutSession { [weak self] session, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let session else {
                    // Nothing to recover; fall back to a fresh start attempt.
                    self.createAndStartSession()
                    return
                }
                session.delegate = self
                self.session = session
                self.builder = session.associatedWorkoutBuilder()
                self.refreshWatchState()
            }
        }
    }

    private func resetSession() {
        session = nil
        builder = nil
        startTries = 0
    }

    // MARK: - Timers

    private func scheduleStartRetry() {
        // Retry after a 15 s backoff while the ride is still active and we have
        // tries left; the machine guards the actual transition (row 13).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            self.apply(.retryTimer(rideActive: self.isRideActive, tries: self.startTries))
        }
    }

    private func scheduleDefaultChoice() {
        // Default-choice timeout: 60 s after the summary appears, apply the
        // rider's default (Save) if they made no choice (Requirement 16.2).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, case .stopping = self.machine.state else { return }
            self.apply(.saveChosen)
        }
    }

    /// Whether the machine still considers the ride active (running/paused).
    private var isRideActive: Bool {
        switch machine.state {
        case .running, .paused, .preparing: return true
        default: return false
        }
    }

    // MARK: - WireWatchState

    private func refreshWatchState() {
        let phase = Self.phase(for: machine.state)
        let reason = Self.reason(for: machine.state)
        let newState = WireWatchState(
            session: phase,
            sessionReason: reason,
            healthAuthorized: healthStore == nil ? false : isWorkoutShareAuthorized(),
            appActive: Self.appIsActive,
            displayActive: Self.appIsActive,
            batteryPct: Self.batteryPercent,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hapticsArmed: phase == .running,
            anotherWorkout: reason == .anotherWorkout,
            workoutSaved: Self.saveState(for: machine.state)
        )
        guard newState != watchState else { return }
        watchState = newState
        onStateChange?(newState)
    }

    private func isWorkoutShareAuthorized() -> Bool {
        guard let healthStore else { return false }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Mapping helpers

    private static func initialWatchState(available: Bool) -> WireWatchState {
        WireWatchState(
            session: .none,
            sessionReason: nil,
            healthAuthorized: available ? nil : false,
            appActive: appIsActive,
            displayActive: appIsActive,
            batteryPct: batteryPercent,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hapticsArmed: false,
            anotherWorkout: false,
            workoutSaved: .none
        )
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

    private static func reason(for state: WorkoutSessionStateMachine.State) -> WireSessionReason? {
        switch state {
        case let .failed(reason): return reason
        case let .unavailable(reason): return reason
        default: return nil
        }
    }

    private static func saveState(for state: WorkoutSessionStateMachine.State) -> WireWorkoutSaveState {
        if case let .ended(save) = state { return save }
        return .none
    }

    private static var batteryPercent: Int {
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return 0 }
        return min(100, max(0, Int((level * 100).rounded())))
        #else
        return 0
        #endif
    }

    private static var appIsActive: Bool {
        #if os(watchOS)
        WKApplication.shared().applicationState == .active
        #else
        false
        #endif
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HKWorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                self.apply(.sessionRunning)
            case .ended, .stopped:
                // The system ended the session unexpectedly while the ride is
                // active → the machine routes to failed(systemEnded) + retry.
                if self.isRideActive {
                    self.apply(.systemEndedSession)
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Another workout started elsewhere takes priority; otherwise a
            // generic start/system failure.
            if (error as? HKError)?.code == .errorAnotherWorkoutSessionStarted {
                self.apply(.anotherWorkoutStarted)
            } else {
                self.apply(.systemEndedSession)
            }
        }
    }
}
