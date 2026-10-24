import Foundation

/// Maps `RideRemoteCommand`s from an eyes-free surface onto the **existing**
/// ride engine intents and the camera actions, without modifying the ride
/// engine (rear-camera spec Requirement 13.2; design "Eyes-free surfaces:
/// Commands"). The same pattern the crash-response `RideSessionBridge` uses:
/// read the ride view model's public state and call its public intents only.
///
/// Command mapping:
/// - `pause` / `resume` → `RideSessionViewModel.pause()` / `resume()`,
///   idempotent (a command in the wrong state is `.ignored(.invalidState)`).
/// - `saveClip` → the injected pinner action; its `ClipSaveOutcome` becomes a
///   reply (`saved`/`pending` ⇒ `.accepted`, `nothingToSave` ⇒ ignored).
/// - `stop(confirmedByHold:)` → `RideSessionViewModel.stop()` **only** when the
///   hold is confirmed, so an accidental wrist tap can never end a ride
///   (otherwise `.ignored(.notConfirmed)`).
/// - `cancelCrashCountdown` → the injected crash-cancel action.
///
/// `@MainActor` (project default isolation): the ride view model is main-actor
/// isolated, and so are the injected actions.
@MainActor
final class RideRemoteBridge {
    private let rideViewModel: RideSessionViewModel
    private let saveClip: () -> ClipSaveOutcome
    private let cancelCrashCountdown: () -> Void

    init(
        rideViewModel: RideSessionViewModel,
        saveClip: @escaping () -> ClipSaveOutcome,
        cancelCrashCountdown: @escaping () -> Void
    ) {
        self.rideViewModel = rideViewModel
        self.saveClip = saveClip
        self.cancelCrashCountdown = cancelCrashCountdown
    }

    /// Apply a command and return the reply for the surface.
    @discardableResult
    func handle(_ command: RideRemoteCommand) -> RideRemoteCommandReply {
        switch command {
        case .pause:
            return applyPause()
        case .resume:
            return applyResume()
        case .saveClip:
            return applySaveClip()
        case let .stop(confirmedByHold):
            return applyStop(confirmedByHold: confirmedByHold)
        case .cancelCrashCountdown:
            cancelCrashCountdown()
            return .accepted
        }
    }

    // MARK: - Private

    private func applyPause() -> RideRemoteCommandReply {
        let state = rideViewModel.rideState
        guard state == .recording || state == .signalLost else {
            return .ignored(reason: .invalidState)
        }
        rideViewModel.pause()
        return .accepted
    }

    private func applyResume() -> RideRemoteCommandReply {
        guard rideViewModel.rideState == .paused else {
            return .ignored(reason: .invalidState)
        }
        rideViewModel.resume()
        return .accepted
    }

    private func applySaveClip() -> RideRemoteCommandReply {
        switch saveClip() {
        case .saved, .pending:
            return .accepted
        case .nothingToSave:
            return .ignored(reason: .nothingToSave)
        }
    }

    private func applyStop(confirmedByHold: Bool) -> RideRemoteCommandReply {
        guard confirmedByHold else { return .ignored(reason: .notConfirmed) }
        guard rideViewModel.rideState.isActive else {
            return .ignored(reason: .invalidState)
        }
        rideViewModel.stop()
        return .accepted
    }
}
