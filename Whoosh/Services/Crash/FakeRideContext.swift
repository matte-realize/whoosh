import Foundation

/// Scriptable read-only `RideContext` for tests and previews.
///
/// Lives under `Services/Crash/` so previews and the composition root can inject
/// it; tests reach it via `@testable import`. Every property is directly
/// settable so a test can model any ride state and fix freshness, then read it
/// back through the protocol.
final class FakeRideContext: RideContext {
    var isRideActive: Bool
    var isRecordingOrSignalLost: Bool
    var latestAcceptedFix: RideFix?
    var currentRideID: UUID?

    init(
        isRideActive: Bool = false,
        isRecordingOrSignalLost: Bool = false,
        latestAcceptedFix: RideFix? = nil,
        currentRideID: UUID? = nil
    ) {
        self.isRideActive = isRideActive
        self.isRecordingOrSignalLost = isRecordingOrSignalLost
        self.latestAcceptedFix = latestAcceptedFix
        self.currentRideID = currentRideID
    }
}
