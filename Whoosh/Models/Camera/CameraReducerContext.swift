import Foundation

/// The read-only context the camera reducer needs to evaluate guards (rear-camera
/// spec Requirement 5.9, design "Camera recording state machine"). A value type
/// the coordinator snapshots from the current app/device state before each
/// reduce, so the reducer stays pure and deterministic.
///
/// Foundation-only value type; `Equatable`, `Sendable`. It carries no framework
/// types and no GPS — a camera state change never reads or writes ride location.
struct CameraReducerContext: Equatable, Sendable {
    /// The camera permission state (row 1/2/18 guards).
    let permission: CameraPermissionStatus
    /// Whether free space is at/above the start minimum (row 1/3 guard).
    let storageMeetsStartMinimum: Bool
    /// The profile the selector resolved to run, or `nil` if unavailable (row 1).
    let resolvedProfile: CaptureProfile?
    /// Whether a ride is currently active (rows 10/11/15–17/22 guards).
    let rideActive: Bool
    /// How many start attempts have already been made (rows 5/6 guard).
    let startAttempts: Int
    /// Whether the single writer-failure restart has already been tried (rows 19/20).
    let writerRestartTried: Bool
    /// How many `failed`-state retries have happened (row 22 cap, max 3).
    let failedRetryCount: Int
    /// Whether the thermal step-up hysteresis is satisfied right now (row 8).
    let stepUpHysteresisSatisfied: Bool
    /// The profile to step to on a thermal step down/up (rows 7/8); `nil` keeps
    /// the current profile.
    let steppedProfile: CaptureProfile?
    /// The tuning values (delays, caps).
    let tuning: RideCameraTuning

    init(
        permission: CameraPermissionStatus,
        storageMeetsStartMinimum: Bool,
        resolvedProfile: CaptureProfile?,
        rideActive: Bool,
        startAttempts: Int = 0,
        writerRestartTried: Bool = false,
        failedRetryCount: Int = 0,
        stepUpHysteresisSatisfied: Bool = false,
        steppedProfile: CaptureProfile? = nil,
        tuning: RideCameraTuning = RideCameraTuning()
    ) {
        self.permission = permission
        self.storageMeetsStartMinimum = storageMeetsStartMinimum
        self.resolvedProfile = resolvedProfile
        self.rideActive = rideActive
        self.startAttempts = startAttempts
        self.writerRestartTried = writerRestartTried
        self.failedRetryCount = failedRetryCount
        self.stepUpHysteresisSatisfied = stepUpHysteresisSatisfied
        self.steppedProfile = steppedProfile
        self.tuning = tuning
    }
}

/// The result of one camera reduction: the next state and the ordered effects
/// the coordinator should perform.
struct CameraReduction: Equatable, Sendable {
    let state: CameraRecordingState
    let effects: [CameraEffect]

    init(state: CameraRecordingState, effects: [CameraEffect] = []) {
        self.state = state
        self.effects = effects
    }
}
