import Foundation

/// The watch's reported state, sent watch → phone (watch-companion design
/// "`WireWatchState`"; Requirement 4, 10). Lets the phone's channel evaluator
/// decide whether the watch is haptics-ready. Values are enums, numbers, and
/// booleans only.
///
/// `healthAuthorized` is `nil` when the watch does not yet know (the design's
/// "Bool/unknown"); `sessionReason` accompanies a `failed`/`unavailable`
/// session phase.
public struct WireWatchState: Equatable, Codable, Sendable {
    public var session: WireWorkoutSessionPhase
    public var sessionReason: WireSessionReason?
    public var healthAuthorized: Bool?
    public var appActive: Bool
    public var displayActive: Bool
    public var batteryPct: Int
    public var lowPowerMode: Bool
    public var hapticsArmed: Bool
    public var anotherWorkout: Bool
    public var workoutSaved: WireWorkoutSaveState

    public init(
        session: WireWorkoutSessionPhase,
        sessionReason: WireSessionReason? = nil,
        healthAuthorized: Bool? = nil,
        appActive: Bool,
        displayActive: Bool,
        batteryPct: Int,
        lowPowerMode: Bool = false,
        hapticsArmed: Bool = false,
        anotherWorkout: Bool = false,
        workoutSaved: WireWorkoutSaveState = .none
    ) {
        self.session = session
        self.sessionReason = sessionReason
        self.healthAuthorized = healthAuthorized
        self.appActive = appActive
        self.displayActive = displayActive
        self.batteryPct = batteryPct
        self.lowPowerMode = lowPowerMode
        self.hapticsArmed = hapticsArmed
        self.anotherWorkout = anotherWorkout
        self.workoutSaved = workoutSaved
    }
}
