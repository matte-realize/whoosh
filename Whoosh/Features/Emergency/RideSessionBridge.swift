import Foundation
import Observation

/// Observes the ride engine and bridges it to the crash subsystem (spec
/// Requirement 5.4, 5.8, 7.5, 13.1; crash-response task 15).
///
/// The ride engine (`RideSessionViewModel`) is **not modified** beyond the
/// single read-only `currentRideID` accessor approved in design O7. This bridge:
/// - conforms to the read-only `RideContext` the coordinator consumes
///   (ride active/recordable, freshest accepted fix, current ride id);
/// - observes the view model's `rideState` and `points` with Observation
///   tracking and re-evaluates arming whenever they change;
/// - starts the `CrashDetector` when `CrashArming` becomes armed and stops it
///   when it becomes disarmed, so detection runs only while recording/signalLost
///   with consent, a label, and a reachable contact (O10).
///
/// Arming also depends on inputs the ride engine does not know about (the
/// feature toggle, consent, reachable contacts); callers invoke
/// `reevaluateArming()` when those change (for example after editing contacts or
/// revoking consent).
///
/// A detector failure never affects ride recording (Requirement 5.8): this
/// bridge only reads ride state and calls `start()`/`stop()`, which are
/// non-blocking and must never stop the ride.
@MainActor
final class RideSessionBridge: RideContext {
    // MARK: Injected

    @ObservationIgnored private let rideViewModel: RideSessionViewModel
    @ObservationIgnored private let detector: CrashDetector
    /// Supplies the non-ride arming inputs (enabled / consent current / label /
    /// reachable-contact count) when arming is evaluated.
    @ObservationIgnored private let armingInputs: () -> ArmingInputs

    /// The non-ride arming inputs, snapshotted at evaluation time.
    struct ArmingInputs {
        let enabled: Bool
        let consentCurrent: Bool
        let riderLabelPresent: Bool
        let reachableContactCount: Int

        init(enabled: Bool, consentCurrent: Bool, riderLabelPresent: Bool, reachableContactCount: Int) {
            self.enabled = enabled
            self.consentCurrent = consentCurrent
            self.riderLabelPresent = riderLabelPresent
            self.reachableContactCount = reachableContactCount
        }
    }

    /// Whether the detector is currently started by this bridge.
    private(set) var isDetectorArmed = false

    init(
        rideViewModel: RideSessionViewModel,
        detector: CrashDetector,
        armingInputs: @escaping () -> ArmingInputs
    ) {
        self.rideViewModel = rideViewModel
        self.detector = detector
        self.armingInputs = armingInputs
    }

    // MARK: - RideContext (read-only projection)

    var isRideActive: Bool { rideViewModel.rideState.isActive }

    var isRecordingOrSignalLost: Bool {
        switch rideViewModel.rideState {
        case .recording, .signalLost: return true
        case .idle, .paused, .finished: return false
        }
    }

    /// The freshest accepted route point as a `RideFix`, or `nil` when the ride
    /// has produced none. Uses only the engine's published `points`.
    var latestAcceptedFix: RideFix? {
        guard let point = rideViewModel.points.last else { return nil }
        return RideFix(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracy: point.horizontalAccuracyMeters,
            timestamp: point.timestamp
        )
    }

    var currentRideID: UUID? { rideViewModel.currentRideID }

    // MARK: - Observation + arming

    /// Begin observing the ride engine. Evaluates arming once, then re-arms the
    /// Observation tracking after each change to `rideState`/`points`.
    func start() {
        reevaluateArming()
        observeRide()
    }

    /// Stop observing and disarm the detector.
    func stop() {
        setArmed(false)
    }

    /// Track `rideState` and `points`; when either changes, re-evaluate arming
    /// and re-install the tracking (Observation is one-shot per access).
    private func observeRide() {
        withObservationTracking {
            _ = rideViewModel.rideState
            _ = rideViewModel.points
        } onChange: { [weak self] in
            // `onChange` fires just before the value changes; hop to the main
            // actor to read the new value and re-install tracking.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reevaluateArming()
                self.observeRide()
            }
        }
    }

    /// Recompute `CrashArming` from the current ride state and the injected
    /// non-ride inputs, and start/stop the detector if the result changed.
    func reevaluateArming() {
        let inputs = armingInputs()
        let armed = CrashArming.isArmed(
            CrashArming.Input(
                rideState: rideViewModel.rideState,
                enabled: inputs.enabled,
                consentCurrent: inputs.consentCurrent,
                riderLabelPresent: inputs.riderLabelPresent,
                reachableContactCount: inputs.reachableContactCount
            )
        )
        setArmed(armed)
    }

    private func setArmed(_ armed: Bool) {
        guard armed != isDetectorArmed else { return }
        isDetectorArmed = armed
        if armed {
            detector.start()
        } else {
            detector.stop()
        }
    }
}
