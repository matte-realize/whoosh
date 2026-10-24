import Foundation
import Testing
@testable import Whoosh

/// Tests for `RideFlowCoordinator` (task 23, Requirement 1.5).
///
/// Pure mapping from `RideState` (+ the finished ride) to the full-screen-cover
/// presentation decision, so the view layer only renders the result.
struct RideFlowCoordinatorTests {
    private func sampleRide() -> Ride {
        Ride(
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_600),
            points: [],
            summary: RideSummary(distanceMeters: 1_000, activeDuration: 600, averageSpeedMetersPerSecond: 1.6)
        )
    }

    // MARK: - coverContent

    @Test func idleShowsNoCover() {
        #expect(RideFlowCoordinator.coverContent(for: .idle, finishedRide: nil) == .none)
        #expect(RideFlowCoordinator.isCoverPresented(for: .idle, finishedRide: nil) == false)
    }

    @Test(arguments: [RideState.recording, .paused, .signalLost])
    func activeStatesShowActiveRide(state: RideState) {
        #expect(RideFlowCoordinator.coverContent(for: state, finishedRide: nil) == .activeRide)
        #expect(RideFlowCoordinator.isCoverPresented(for: state, finishedRide: nil))
    }

    @Test func finishedWithRideShowsSummary() {
        let ride = sampleRide()
        #expect(
            RideFlowCoordinator.coverContent(for: .finished, finishedRide: ride) == .summary(ride)
        )
        #expect(RideFlowCoordinator.isCoverPresented(for: .finished, finishedRide: ride))
    }

    @Test func finishedWithoutRideShowsNoCover() {
        // Defensive: a finished state with no ride has nothing to present.
        #expect(RideFlowCoordinator.coverContent(for: .finished, finishedRide: nil) == .none)
        #expect(RideFlowCoordinator.isCoverPresented(for: .finished, finishedRide: nil) == false)
    }

    @Test func activeStatesIgnoreAnyFinishedRide() {
        // While still active, the cover shows the live screen even if a stale
        // finished ride is somehow present.
        let ride = sampleRide()
        #expect(RideFlowCoordinator.coverContent(for: .recording, finishedRide: ride) == .activeRide)
    }
}
