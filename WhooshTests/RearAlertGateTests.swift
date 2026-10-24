import Foundation
import Testing
@testable import Whoosh

/// Truth-table tests for the pure normal-mode rear-vehicle alert gate
/// (demo-mode task 2, Requirements 4.1/4.2).
struct RearAlertGateTests {
    private static let tuning = DemoTuning()   // threshold 2 m/s

    // MARK: recording

    @Test func recordingAndFastDelivers() {
        #expect(RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 5, tuning: Self.tuning
        ))
    }

    @Test func recordingButSlowSuppressed() {
        #expect(!RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 1, tuning: Self.tuning
        ))
    }

    @Test func recordingAtExactThresholdSuppressed() {
        // Strictly greater than the threshold — at exactly 2 m/s the gate closes.
        #expect(!RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 2, tuning: Self.tuning
        ))
    }

    @Test func recordingJustAboveThresholdDelivers() {
        #expect(RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 2.001, tuning: Self.tuning
        ))
    }

    // MARK: non-recording states always suppressed

    @Test(arguments: [RideState.paused, .signalLost, .idle, .finished])
    func nonRecordingStatesSuppressedEvenWhenFast(state: RideState) {
        #expect(!RearAlertGate.shouldDeliver(
            rideState: state, currentSpeed: 10, tuning: Self.tuning
        ))
    }

    // MARK: configurable threshold

    @Test func customThresholdIsHonored() {
        let tuning = DemoTuning(minAlertSpeedMetersPerSecond: 5)
        #expect(!RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 4, tuning: tuning
        ))
        #expect(RearAlertGate.shouldDeliver(
            rideState: .recording, currentSpeed: 6, tuning: tuning
        ))
    }
}
