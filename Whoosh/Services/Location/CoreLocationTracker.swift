import CoreLocation
import Foundation

/// Production `LocationTracking` wrapping `CLLocationManager`.
///
/// The ride engine never imports Core Location; this is the single concrete type
/// (plus `CoreLocationMapping`) that does. It maps `CLLocation` → `RoutePoint`,
/// `CLAuthorizationStatus` → `LocationAuthorizationStatus`, and
/// `didFailWithError` → `LocationFailure`, delivering everything through the
/// `LocationTracking` callbacks on the main actor.
///
/// Concurrency: the type runs on the main actor (project default isolation), so
/// callbacks are safe to use directly from `@MainActor` view models. The
/// `CLLocationManagerDelegate` methods are `nonisolated` (Core Location calls
/// them without an actor guarantee) and hop back to the main actor before
/// touching any state or firing callbacks.
///
/// No background modes: `allowsBackgroundLocationUpdates` is never enabled and
/// no background `location` mode is declared — the MVP is foreground + screen-on
/// only.
final class CoreLocationTracker: NSObject, LocationTracking {
    private let manager: CLLocationManager

    var onAuthorizationChange: ((LocationAuthorizationStatus) -> Void)?
    var onLocation: ((RoutePoint) -> Void)?
    var onFailure: ((LocationFailure) -> Void)?

    override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        // Foreground-only: never auto-pause and never enable background updates.
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Current authorization, mapped from the manager's status.
    var authorizationStatus: LocationAuthorizationStatus {
        CoreLocationMapping.authorizationStatus(from: manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating(accuracy: TrackingAccuracy) {
        // No synchronous `locationServicesEnabled()` check here: it blocks the
        // main thread (Apple warns about it). With services off device-wide the
        // authorization reads as denied and `didFailWithError` reports it, which
        // the existing denial path surfaces (design error table / Req 2.6).
        manager.desiredAccuracy = CoreLocationMapping.desiredAccuracy(for: accuracy)
        manager.distanceFilter = CoreLocationMapping.distanceFilter(for: accuracy)
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        // Fully stop updates. Callbacks are owned/cleared by the view model
        // (Req 11.3: no leaked tracking after a ride ends).
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for location in locations {
                self.onLocation?(CoreLocationMapping.routePoint(from: location))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        // `CLAuthorizationStatus` is Sendable; capture it before hopping.
        let systemStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.onAuthorizationChange?(
                CoreLocationMapping.authorizationStatus(from: systemStatus)
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Reduce to a Sendable failure before hopping (avoids sending `Error`).
        let failure: LocationFailure
        if let clError = error as? CLError, clError.code == .denied {
            failure = .denied
        } else {
            failure = .unknown(String(describing: (error as? CLError)?.code ?? .locationUnknown))
        }
        Task { @MainActor [weak self] in
            self?.onFailure?(failure)
        }
    }
}
