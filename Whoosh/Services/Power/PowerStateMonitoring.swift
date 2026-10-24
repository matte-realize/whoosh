import Foundation

/// Observes the device's low-power / thermal condition so the ride engine can
/// degrade gracefully instead of crashing or draining the battery
/// (Requirement 11.2).
///
/// Abstracted behind a protocol for the same reason as `LocationTracking`: the
/// view model stays testable (a fake reports Low Power Mode on command) and the
/// engine never has to read `ProcessInfo` directly. The concrete
/// `ProcessInfoPowerMonitor` is the only type that touches `ProcessInfo`.
///
/// Callbacks are delivered on the main actor (project default isolation), so a
/// `@MainActor` view model can use them directly.
protocol PowerStateMonitoring: AnyObject {
    /// `true` when the device is in Low Power Mode right now.
    var isLowPowerModeEnabled: Bool { get }

    /// `true` when the device is thermally throttled (serious/critical), so the
    /// app should back off from high-accuracy GPS.
    var isThermallyThrottled: Bool { get }

    /// Invoked whenever the low-power or thermal condition changes. The ride
    /// engine uses this to pick an accuracy profile for the *next* location
    /// request; it never forces a restart of the current one.
    var onPowerStateChange: (() -> Void)? { get set }

    /// Begin observing power/thermal notifications.
    func startMonitoring()

    /// Stop observing (released when a ride ends, like location tracking).
    func stopMonitoring()
}

extension PowerStateMonitoring {
    /// Convenience: the device is in a constrained state (either Low Power Mode
    /// or thermal throttling) and the engine should prefer `.balanced` accuracy.
    var prefersReducedAccuracy: Bool {
        isLowPowerModeEnabled || isThermallyThrottled
    }

    /// The accuracy profile to use for the next location request, degrading a
    /// requested `.high` to `.balanced` while constrained (Requirement 11.2).
    /// `.balanced` is never upgraded.
    func effectiveAccuracy(requested: TrackingAccuracy) -> TrackingAccuracy {
        guard prefersReducedAccuracy else { return requested }
        return .balanced
    }
}
