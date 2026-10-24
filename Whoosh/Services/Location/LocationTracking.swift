import Foundation

/// Abstracts Core Location so the ride engine is testable with injected
/// fixtures (Requirements 2.1, 4.1, 4.6). The engine never imports Core
/// Location; `CoreLocationTracker` is the only concrete type that does, and
/// `FakeLocationTracker` scripts events for tests and previews.
///
/// Callbacks (rather than an `AsyncStream`) are used deliberately: they keep the
/// fake trivial and avoid task-lifetime questions during the hackathon (see the
/// design's "Why callbacks over an AsyncStream" note). `AnyObject` because a
/// tracker is a long-lived reference type owning the system manager.
///
/// Callbacks are delivered on the main actor in this project (default MainActor
/// isolation), so they are safe to use directly from `@MainActor` view models.
protocol LocationTracking: AnyObject {
    /// The current authorization state.
    var authorizationStatus: LocationAuthorizationStatus { get }

    /// Invoked whenever authorization changes (including returning from
    /// Settings), so the UI can update without a restart (Requirement 2.4).
    var onAuthorizationChange: ((LocationAuthorizationStatus) -> Void)? { get set }

    /// Invoked for each location sample mapped to a `RoutePoint`.
    var onLocation: ((RoutePoint) -> Void)? { get set }

    /// Invoked when the location subsystem fails.
    var onFailure: ((LocationFailure) -> Void)? { get set }

    /// Request "When In Use" authorization (the only level the MVP requests).
    func requestWhenInUseAuthorization()

    /// Begin delivering location updates using the given accuracy profile.
    func startUpdating(accuracy: TrackingAccuracy)

    /// Stop delivering updates and release the system manager's hold so no
    /// tracking leaks after a ride ends (Requirement 11.3).
    func stopUpdating()
}
