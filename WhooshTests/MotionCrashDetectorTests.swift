import Foundation
import Testing
@testable import Whoosh

/// Tests for the `MotionCrashDetector` adapter's wiring (crash-response task 33).
/// The signal-processing math is covered by `MotionCrashSignalCoreTests`; here we
/// drive the adapter's device-free seam (`ingestAndEvaluate`) to confirm it feeds
/// the core, reads speed from the shared `RideSpeedSnapshot`, emits a `motion`
/// signal on a trigger, and only emits while monitoring.
///
/// No device or Core Motion is involved — `ingestAndEvaluate` is the same path
/// `handle(_:)` uses once it has turned a `CMDeviceMotion` into a magnitude.
@MainActor
struct MotionCrashDetectorTests {
    private let g = MotionCrashTuning.gravity
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func makeDetector(speed: Double?) -> (MotionCrashDetector, RideSpeedSnapshot, Box) {
        let snapshot = RideSpeedSnapshot(speed: speed)
        let detector = MotionCrashDetector(
            clock: TestClock(now: t0),
            speedSnapshot: snapshot
        )
        let box = Box()
        detector.onSignal = { box.signals.append($0) }
        return (detector, snapshot, box)
    }

    /// Feed a steady baseline, then an impact, then stillness; return the trigger
    /// evaluation time.
    private func driveCrashTrace(_ detector: MotionCrashDetector, tuning: MotionCrashTuning = MotionCrashTuning()) {
        var t = t0
        // 3 s riding at ~1 g jitter.
        while t <= t0.addingTimeInterval(3.0) {
            detector.ingestAndEvaluate(accelerationMagnitude: 1.0 * g, at: t)
            t = t.addingTimeInterval(0.05)
        }
        // Impact.
        let impact = t
        detector.ingestAndEvaluate(accelerationMagnitude: 6.0 * g, at: impact)
        // Stillness for the window.
        var s = impact.addingTimeInterval(0.1)
        let end = impact.addingTimeInterval(tuning.stillnessWindow + 0.5)
        while s <= end {
            detector.ingestAndEvaluate(accelerationMagnitude: 0.05 * g, at: s)
            s = s.addingTimeInterval(0.05)
        }
    }

    @Test func emitsMotionSignalForCrashTraceWhileMonitoring() {
        let (detector, _, box) = makeDetector(speed: 7.0)
        detector.start()
        driveCrashTrace(detector)

        #expect(box.signals.count == 1)
        let signal = box.signals.first
        #expect(signal?.source == MotionCrashDetector.sourceLabel)
        #expect(signal?.isDrill == false)
        #expect((signal?.confidence ?? 0) >= MotionCrashTuning().triggerScore)
    }

    @Test func doesNotEmitWhenSpeedUnknownBlocksTheSpeedDropTerm() {
        // No speed ⇒ the speed-drop term is 0; a bump that is otherwise identical
        // to the crash trace does not clear the bar.
        let (detector, _, box) = makeDetector(speed: nil)
        detector.start()
        driveCrashTrace(detector)
        #expect(box.signals.isEmpty)
    }

    @Test func stopHaltsEmission() {
        let (detector, _, box) = makeDetector(speed: 7.0)
        detector.start()
        detector.stop()
        driveCrashTrace(detector)
        #expect(box.signals.isEmpty)
        #expect(detector.isMonitoring == false)
    }

    @Test func samplingProfileIntervalsAreBatteryAware() {
        #expect(MotionCrashDetector.MotionSamplingProfile.standard.updateInterval
                < MotionCrashDetector.MotionSamplingProfile.efficient.updateInterval)
    }

    @Test func speedSnapshotIsThreadSafeReadWrite() {
        let snapshot = RideSpeedSnapshot()
        #expect(snapshot.current == nil)
        snapshot.update(5.5)
        #expect(snapshot.current == 5.5)
        snapshot.update(nil)
        #expect(snapshot.current == nil)
    }

    /// A reference box so the `onSignal` closure can accumulate across calls.
    final class Box {
        var signals: [CrashSignal] = []
    }
}

/// Tests for the `CompositeCrashDetector` fan-in (crash-response task 33): both
/// children's signals reach the single `onSignal`, and start/stop forward.
@MainActor
struct CompositeCrashDetectorTests {
    @Test func relaysSignalsFromEitherChild() {
        let a = FakeCrashDetector()
        let b = FakeCrashDetector()
        let composite = CompositeCrashDetector([a, b])
        var received: [String] = []
        composite.onSignal = { received.append($0.source) }

        composite.start()
        a.emit(source: "motion")
        b.emit(source: "simulator")

        #expect(received == ["motion", "simulator"])
    }

    @Test func startStopForwardToAllChildren() {
        let a = FakeCrashDetector()
        let b = FakeCrashDetector()
        let composite = CompositeCrashDetector([a, b])

        composite.start()
        #expect(a.startCount == 1)
        #expect(b.startCount == 1)

        composite.stop()
        #expect(a.stopCount == 1)
        #expect(b.stopCount == 1)
    }
}
