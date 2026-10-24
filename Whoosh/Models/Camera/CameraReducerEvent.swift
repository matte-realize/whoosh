import Foundation

/// The events that drive the camera recording state machine (rear-camera spec
/// Requirement 5.9, design "Camera recording state machine" rows 1–24). Each
/// event is pure data; the reducer maps `(state, event, context) → (state,
/// effects)` with no I/O.
///
/// Foundation-only enum; `Equatable`, `Sendable`. Associated values carry only
/// Foundation/Models types (never `CMTime` or any framework type).
enum CameraReducerEvent: Equatable, Sendable {
    /// The ride started with the rear-camera feature enabled (rows 1–3).
    case rideStarted
    /// The capture session reported it is running (row 4).
    case sessionRunning
    /// A runtime error or the start timeout elapsed while preparing (rows 5–6).
    case startFailure
    /// Thermal/battery pressure asks to step the profile down (row 7).
    case thermalStepDown
    /// Thermal pressure eased; attempt a step up (row 8).
    case thermalStepUp
    /// The capture session was interrupted with a reason (rows 9).
    case interrupted(InterruptionReasonKind)
    /// An interruption ended (rows 10–11).
    case interruptionEnded
    /// Thermal critical / system-pressure forced a stop (row 12).
    case thermalCriticalStop
    /// Free space dropped below the stop floor (row 13).
    case storageStop
    /// Battery reached the floor and the device is not charging (row 14).
    case batteryStop
    /// A stop condition cleared and the camera may resume (rows 15–17).
    case resumeConditionCleared
    /// Camera permission was revoked mid-ride (row 18).
    case permissionRevoked
    /// The asset writer failed (rows 19–20).
    case writerFailed
    /// The ride ended or the feature was disabled (row 21).
    case rideEndedOrFeatureDisabled
    /// A retry timer fired while in `failed` (row 22).
    case retryTimer
    /// The ride was paused or resumed; the camera keeps recording (row 23).
    case ridePausedOrResumed
}
