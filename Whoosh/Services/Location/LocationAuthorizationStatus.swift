import Foundation

/// App-level location authorization state, decoupled from Core Location's
/// `CLAuthorizationStatus` so the ride engine and view models never import
/// Core Location (layering table). `CoreLocationTracker` maps the system status
/// onto these cases.
enum LocationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways
}
