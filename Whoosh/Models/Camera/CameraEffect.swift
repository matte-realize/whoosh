import Foundation

/// A side effect the camera reducer asks the coordinator to perform, returned as
/// **data** (rear-camera spec Requirement 5.9, design "Camera recording state
/// machine"). The reducer is pure; the coordinator (with the capture service,
/// recorder, clock, and alert manager) executes these.
///
/// Foundation-only enum; `Equatable`, `Sendable`. **No effect ever touches GPS**
/// (property-checked in the reducer tests) — a camera state change never affects
/// ride recording.
enum CameraEffect: Equatable, Sendable {
    /// Start the capture session and open the first segment.
    case startSession(CaptureProfile)
    /// Lower the frame rate live or change resolution at the next boundary.
    case applyProfileStep(CaptureProfile)
    /// Finalize the open segment (used on interruption/stop, via a background task).
    case finalizeSegment
    /// Open a new segment, flagging a discontinuity for consumers (after resume).
    case openNewSegmentWithDiscontinuity
    /// Discard the current (bad) segment after a writer failure.
    case discardSegment
    /// Fully tear down the capture session (ride end / feature off / terminal).
    case teardownSession
    /// Finish any pending pins before teardown (ride end).
    case finishPendingPins
    /// Delete the unpinned ring segments (ride end; privacy default).
    case deleteUnpinnedSegments
    /// Schedule a retry after the given delay (preparing retry / failed retry).
    case scheduleRetry(after: TimeInterval)
    /// Schedule thermal/storage/battery polling once recording starts.
    case schedulePolling
    /// Publish the current `RideStatus` snapshot to the eyes-free surface.
    case publishStatus
    /// Tell the rider (eyes-free + ride-mode amber dot) with this alert.
    case alert(CameraAlert)
}

/// The camera-related rider notifications the reducer can request. Maps to the
/// additive `AlertKind` cases (design "AlertKind additions"); kept as a small
/// Foundation-only enum so the reducer stays pure. Camera trouble is never
/// silent — the rider cannot see the screen.
enum CameraAlert: Equatable, Sendable {
    /// Could not start the camera because permission is not authorized.
    case notStartedPermission
    /// Could not start the camera because free space is below the start minimum.
    case notStartedStorage
    /// The camera was interrupted (notice after the threshold).
    case interrupted
    /// The camera resumed after an interruption.
    case resumed
    /// Recording was reduced (degraded) for a reason.
    case reduced
    /// The camera stopped for a reason (thermal/storage/battery/permission/failed).
    case stopped(CameraStopReason)
}
