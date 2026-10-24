import Testing
@testable import Whoosh

/// Tests for the power-state abstraction used in the resilience pass (task 24,
/// Requirement 11.2). Verifies the accuracy-degradation policy and the fake.
@MainActor
struct PowerStateMonitoringTests {
    @Test func normalStatePrefersRequestedAccuracy() {
        let monitor = FakePowerMonitor(lowPowerMode: false, thermallyThrottled: false)
        #expect(!monitor.prefersReducedAccuracy)
        #expect(monitor.effectiveAccuracy(requested: .high) == .high)
        #expect(monitor.effectiveAccuracy(requested: .balanced) == .balanced)
    }

    @Test func lowPowerModeDegradesHighToBalanced() {
        let monitor = FakePowerMonitor(lowPowerMode: true)
        #expect(monitor.prefersReducedAccuracy)
        #expect(monitor.effectiveAccuracy(requested: .high) == .balanced)
    }

    @Test func thermalThrottleDegradesHighToBalanced() {
        let monitor = FakePowerMonitor(thermallyThrottled: true)
        #expect(monitor.prefersReducedAccuracy)
        #expect(monitor.effectiveAccuracy(requested: .high) == .balanced)
    }

    @Test func balancedIsNeverUpgraded() {
        let monitor = FakePowerMonitor(lowPowerMode: true)
        #expect(monitor.effectiveAccuracy(requested: .balanced) == .balanced)
    }

    @Test func notifyChangeInvokesCallback() {
        let monitor = FakePowerMonitor()
        var called = 0
        monitor.onPowerStateChange = { called += 1 }
        monitor.notifyChange()
        monitor.notifyChange()
        #expect(called == 2)
    }

    @Test func startAndStopMonitoringTracked() {
        let monitor = FakePowerMonitor()
        #expect(!monitor.isMonitoring)
        monitor.startMonitoring()
        #expect(monitor.isMonitoring)
        monitor.stopMonitoring()
        #expect(!monitor.isMonitoring)
    }
}
