import CoreLocation
import Foundation

/// Pure, compile-checked mapping between Core Location types and the app's
/// framework-free location model.
///
/// Factored out of `CoreLocationTracker` so the mapping logic (the only part
/// that is unit-testable without a device) can be exercised directly by tests.
/// `CoreLocationTracker` owns the live `CLLocationManager`; this enum owns the
/// translation rules.
///
/// The pure functions run on the main actor (project default isolation); the
/// tracker's `nonisolated` delegate methods hop to the main actor before
/// mapping. Tests exercise them from a `@MainActor` context.
///
/// This file (and `CoreLocationTracker`) are the only non-test files allowed to
/// import Core Location (layering table).
enum CoreLocationMapping {
    /// Map a `CLLocation` to a `RoutePoint`.
    ///
    /// An invalid fix (`horizontalAccuracy < 0`) is passed through with its
    /// negative accuracy intact so the view model's acceptance filter discards
    /// it — the mapping layer does not silently drop points.
    static func routePoint(from location: CLLocation) -> RoutePoint {
        RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            speedMetersPerSecond: location.speed,
            horizontalAccuracyMeters: location.horizontalAccuracy
        )
    }

    /// Map a `CLAuthorizationStatus` to the app's `LocationAuthorizationStatus`.
    static func authorizationStatus(
        from status: CLAuthorizationStatus
    ) -> LocationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        case .authorizedAlways:
            return .authorizedAlways
        @unknown default:
            return .denied
        }
    }

    /// Map a Core Location error to a `LocationFailure`.
    ///
    /// A `CLError.denied` becomes `.denied`; everything else becomes
    /// `.unknown` carrying a short description for diagnostics only (never shown
    /// raw to the user — Requirement 11.4 is handled in the view model/UI).
    static func failure(from error: Error) -> LocationFailure {
        if let clError = error as? CLError, clError.code == .denied {
            return .denied
        }
        return .unknown(String(describing: (error as? CLError)?.code ?? .locationUnknown))
    }

    /// Core Location desired accuracy for a `TrackingAccuracy` profile.
    static func desiredAccuracy(for accuracy: TrackingAccuracy) -> CLLocationAccuracy {
        switch accuracy {
        case .high:
            return kCLLocationAccuracyBest
        case .balanced:
            return kCLLocationAccuracyNearestTenMeters
        }
    }

    /// Core Location distance filter (meters) for a `TrackingAccuracy` profile.
    static func distanceFilter(for accuracy: TrackingAccuracy) -> CLLocationDistance {
        switch accuracy {
        case .high:
            return 5
        case .balanced:
            return 15
        }
    }
}
