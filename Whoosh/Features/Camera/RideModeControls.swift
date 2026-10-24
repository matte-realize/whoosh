import Foundation

/// The in-ride control intents the ride-mode overlay shows while temporarily
/// unlocked: stop, pause/resume, and (when recording) save a clip (owner
/// device-testing feedback: "when unlocked, show a big Stop ride control plus
/// Pause/Resume and Save clip … Make sure a ride can always be stopped from ride
/// mode"). It is a small bag of closures + the current paused flag so the view
/// stays dumb and the composition root (`WhooshApp`) owns the wiring to the
/// `RideSessionViewModel` and the camera coordinator.
///
/// Main-actor because the closures drive main-actor ride/camera intents.
@MainActor
struct RideModeControls {
    /// Whether the ride is currently paused (drives the Pause/Resume label).
    var isPaused: Bool
    /// Finalize the ride (press-and-hold Stop). Always available so a ride can
    /// always be stopped from ride mode.
    var onStop: () -> Void
    /// Toggle pause/resume.
    var onTogglePause: () -> Void
    /// Save a clip from the ring buffer, or `nil` when the camera is off for this
    /// ride (the control is then hidden).
    var onSaveClip: (() -> ClipSaveOutcome)?

    init(
        isPaused: Bool,
        onStop: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onSaveClip: (() -> ClipSaveOutcome)? = nil
    ) {
        self.isPaused = isPaused
        self.onStop = onStop
        self.onTogglePause = onTogglePause
        self.onSaveClip = onSaveClip
    }
}
