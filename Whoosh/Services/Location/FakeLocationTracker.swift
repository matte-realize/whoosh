import Foundation

/// Scriptable `LocationTracking` for tests and SwiftUI previews.
///
/// Lives under `Services/Location/` (not the test target) so previews and the
/// composition root can inject it; tests reach it via `@testable import`.
///
/// Tests drive it imperatively: set `authorizationStatus`, then call
/// `emit(_:)`, `emitPoints(_:)`, `changeAuthorization(_:)`, or `fail(_:)` to
/// deliver events through the matching callback. Callbacks fire synchronously
/// in call order so test expectations are deterministic.
final class FakeLocationTracker: LocationTracking {
    var authorizationStatus: LocationAuthorizationStatus

    var onAuthorizationChange: ((LocationAuthorizationStatus) -> Void)?
    var onLocation: ((RoutePoint) -> Void)?
    var onFailure: ((LocationFailure) -> Void)?

    // MARK: Recorded interactions (for test assertions)

    /// `true` between `startUpdating(accuracy:)` and `stopUpdating()`.
    private(set) var isUpdating = false
    /// The accuracy passed to the most recent `startUpdating(accuracy:)`.
    private(set) var lastAccuracy: TrackingAccuracy?
    /// Number of times authorization was requested.
    private(set) var requestAuthorizationCount = 0

    init(authorizationStatus: LocationAuthorizationStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }

    // MARK: LocationTracking

    func requestWhenInUseAuthorization() {
        requestAuthorizationCount += 1
    }

    func startUpdating(accuracy: TrackingAccuracy) {
        isUpdating = true
        lastAccuracy = accuracy
    }

    func stopUpdating() {
        isUpdating = false
    }

    // MARK: Scripting API (test/preview driven)

    /// Deliver a single location sample through `onLocation`.
    func emit(_ point: RoutePoint) {
        onLocation?(point)
    }

    /// Deliver several location samples in order.
    func emitPoints(_ points: [RoutePoint]) {
        for point in points {
            onLocation?(point)
        }
    }

    /// Change the authorization status and notify through
    /// `onAuthorizationChange`.
    func changeAuthorization(_ status: LocationAuthorizationStatus) {
        authorizationStatus = status
        onAuthorizationChange?(status)
    }

    /// Deliver a failure through `onFailure`.
    func fail(_ failure: LocationFailure) {
        onFailure?(failure)
    }
}
