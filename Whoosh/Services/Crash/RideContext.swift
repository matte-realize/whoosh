import Foundation

/// The freshest accepted location fix the ride engine has produced, exposed to
/// the crash subsystem read-only (spec Requirement 7.5). The MVP tracker already
/// filters by accuracy and plausibility, so these are "accepted" fixes only.
///
/// Foundation-only value type; `Equatable`, `Sendable`.
struct RideFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

/// A **read-only** view of the active ride for the crash subsystem (spec
/// Requirement 7.5, 13.1, design "Integration with RideSessionViewModel").
///
/// The ride engine (`RideSessionViewModel`) is never modified by the crash
/// feature; a `RideSessionBridge` (a later task) observes it and publishes this
/// context. The crash subsystem reads arming inputs (is the ride active, is it
/// in a recordable state) and the freshest accepted fix for the location
/// snapshot. It cannot command the ride in any way.
///
/// ## Contract
/// - **Read-only.** No member mutates ride state; this is a projection only.
/// - **Arming inputs.** `isRideActive` and `isRecordingOrSignalLost` drive
///   `CrashArming`; detection is armed only while `recording`/`signalLost`
///   (design O10), never while paused/idle/finished.
/// - **Freshest accepted fix.** `latestAcceptedFix` is the newest fix the engine
///   accepted, or `nil` when none exists; the snapshot policy decides
///   current/last-known/unavailable.
/// - **Optional ride id.** `currentRideID` is the active ride's id when the
///   engine exposes it (design O7), else `nil`.
///
/// `AnyObject` because the real bridge is a long-lived reference type observing
/// the view model; all members are read on the main actor.
protocol RideContext: AnyObject {
    /// Whether a ride is currently active (`recording`, `paused`, or
    /// `signalLost`).
    var isRideActive: Bool { get }

    /// Whether the ride is in a state detection should be armed in
    /// (`recording` or `signalLost`); `false` while paused/idle/finished.
    var isRecordingOrSignalLost: Bool { get }

    /// The freshest accepted location fix, or `nil` when none exists yet.
    var latestAcceptedFix: RideFix? { get }

    /// The active ride's id when available, else `nil`.
    var currentRideID: UUID? { get }
}
