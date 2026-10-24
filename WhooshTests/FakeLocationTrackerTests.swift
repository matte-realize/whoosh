import Foundation
import Testing
@testable import Whoosh

/// Tests for the scriptable fake location tracker (Requirements 2.1, 4.1, 4.6).
/// Verifies scripted callbacks arrive in order, authorization changes
/// propagate, start/stop state is tracked, and failures are delivered.
struct FakeLocationTrackerTests {
    private static func point(
        _ lat: Double,
        _ lon: Double
    ) -> RoutePoint {
        RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: Date(timeIntervalSince1970: 0),
            speedMetersPerSecond: 5,
            horizontalAccuracyMeters: 5
        )
    }

    @Test func scriptedPointsDeliveredInOrder() {
        let tracker = FakeLocationTracker()
        var received: [RoutePoint] = []
        tracker.onLocation = { received.append($0) }

        let scripted = [
            Self.point(42.0, -71.0),
            Self.point(42.1, -71.1),
            Self.point(42.2, -71.2),
        ]
        tracker.emitPoints(scripted)

        #expect(received == scripted)
    }

    @Test func singleEmitDeliversOnePoint() {
        let tracker = FakeLocationTracker()
        var received: [RoutePoint] = []
        tracker.onLocation = { received.append($0) }

        let point = Self.point(42.0, -71.0)
        tracker.emit(point)

        #expect(received == [point])
    }

    @Test func authorizationChangePropagates() {
        let tracker = FakeLocationTracker(authorizationStatus: .notDetermined)
        var observed: [LocationAuthorizationStatus] = []
        tracker.onAuthorizationChange = { observed.append($0) }

        tracker.changeAuthorization(.authorizedWhenInUse)

        #expect(tracker.authorizationStatus == .authorizedWhenInUse)
        #expect(observed == [.authorizedWhenInUse])
    }

    @Test func failureDelivered() {
        let tracker = FakeLocationTracker()
        var failures: [LocationFailure] = []
        tracker.onFailure = { failures.append($0) }

        tracker.fail(.denied)

        #expect(failures == [.denied])
    }

    @Test func startUpdatingRecordsAccuracyAndState() {
        let tracker = FakeLocationTracker()
        #expect(!tracker.isUpdating)

        tracker.startUpdating(accuracy: .balanced)
        #expect(tracker.isUpdating)
        #expect(tracker.lastAccuracy == .balanced)

        tracker.stopUpdating()
        #expect(!tracker.isUpdating)
    }

    @Test func requestAuthorizationIsCounted() {
        let tracker = FakeLocationTracker()
        tracker.requestWhenInUseAuthorization()
        tracker.requestWhenInUseAuthorization()
        #expect(tracker.requestAuthorizationCount == 2)
    }
}
