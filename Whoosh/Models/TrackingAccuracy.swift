import Foundation

/// GPS accuracy profile applied to the location tracker for a ride.
///
/// The design defines this in the `LocationTracking` section, but it is placed
/// in the Models layer so `RideTuning` (a pure config value type) can reference
/// it without importing a service. The concrete `CoreLocationTracker` maps these
/// cases onto `CLLocationAccuracy` + `distanceFilter`.
///
/// Persisted by `SettingsViewModel` as its `rawValue` in `UserDefaults`
/// (Requirement 14.2), so the raw strings are a stable storage contract.
enum TrackingAccuracy: String, Equatable, Codable, Sendable, CaseIterable {
    /// ~`kCLLocationAccuracyNearestTenMeters`, larger distance filter (battery-friendly).
    case balanced = "Balanced"
    /// ~`kCLLocationAccuracyBest`, small distance filter (most precise).
    case high = "High"
}
