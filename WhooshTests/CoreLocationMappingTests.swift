import CoreLocation
import Foundation
import Testing
@testable import Whoosh

/// Unit tests for the pure Core Location mapping layer (the device-free part of
/// task 11). The live `CLLocationManager` wrapper is verified manually on device.
struct CoreLocationMappingTests {
    @Test func routePointMapsCoordinateTimestampSpeedAndAccuracy() {
        let when = Date(timeIntervalSince1970: 1_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.06),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 0,
            speed: 6.5,
            timestamp: when
        )

        let point = CoreLocationMapping.routePoint(from: location)

        #expect(point.latitude == 42.36)
        #expect(point.longitude == -71.06)
        #expect(point.timestamp == when)
        #expect(point.speedMetersPerSecond == 6.5)
        #expect(point.horizontalAccuracyMeters == 8)
    }

    @Test func routePointPassesThroughNegativeAccuracy() {
        // An invalid fix keeps its negative accuracy so the VM can discard it.
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let point = CoreLocationMapping.routePoint(from: location)

        #expect(point.horizontalAccuracyMeters == -1)
        #expect(point.speedMetersPerSecond == -1)
    }

    @Test(arguments: [
        (CLAuthorizationStatus.notDetermined, LocationAuthorizationStatus.notDetermined),
        (.denied, .denied),
        (.restricted, .restricted),
        (.authorizedWhenInUse, .authorizedWhenInUse),
        (.authorizedAlways, .authorizedAlways),
    ])
    func authorizationStatusMapping(
        system: CLAuthorizationStatus,
        expected: LocationAuthorizationStatus
    ) {
        #expect(CoreLocationMapping.authorizationStatus(from: system) == expected)
    }

    @Test func deniedErrorMapsToDeniedFailure() {
        let error = CLError(.denied)
        #expect(CoreLocationMapping.failure(from: error) == .denied)
    }

    @Test func otherErrorMapsToUnknownFailure() {
        let error = CLError(.network)
        if case .unknown = CoreLocationMapping.failure(from: error) {
            // expected
        } else {
            Issue.record("expected .unknown for a non-denied CLError")
        }
    }

    @Test func highAccuracyMapsToBestWithSmallFilter() {
        #expect(CoreLocationMapping.desiredAccuracy(for: .high) == kCLLocationAccuracyBest)
        #expect(CoreLocationMapping.distanceFilter(for: .high) == 5)
    }

    @Test func balancedAccuracyMapsToTenMetersWithLargerFilter() {
        #expect(
            CoreLocationMapping.desiredAccuracy(for: .balanced)
                == kCLLocationAccuracyNearestTenMeters
        )
        #expect(CoreLocationMapping.distanceFilter(for: .balanced) == 15)
    }
}
