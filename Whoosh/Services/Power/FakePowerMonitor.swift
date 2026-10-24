import Foundation

/// A scriptable `PowerStateMonitoring` for tests and previews.
///
/// Tests flip `isLowPowerModeEnabled` / `isThermallyThrottled` and call
/// `notifyChange()` to simulate the device entering or leaving a constrained
/// state, without touching the real `ProcessInfo`.
final class FakePowerMonitor: PowerStateMonitoring {
    var isLowPowerModeEnabled: Bool
    var isThermallyThrottled: Bool
    private(set) var isMonitoring = false

    var onPowerStateChange: (() -> Void)?

    init(lowPowerMode: Bool = false, thermallyThrottled: Bool = false) {
        self.isLowPowerModeEnabled = lowPowerMode
        self.isThermallyThrottled = thermallyThrottled
    }

    func startMonitoring() { isMonitoring = true }
    func stopMonitoring() { isMonitoring = false }

    /// Simulate a power/thermal state change: set the flags, then call this.
    func notifyChange() { onPowerStateChange?() }
}
