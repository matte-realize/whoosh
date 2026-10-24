import Foundation
import Testing
@testable import Whoosh

/// Focused tests for the pure `PickupDetector` (owner device-testing feedback:
/// "detect the phone being picked up … a large attitude/orientation change").
/// It turns the gravity vector the mount sensor already streams into a single
/// debounced pickup signal; no Core Motion, no clock reads.
struct PickupDetectorTests {
    /// Gravity pointing "down" through the device while mounted upright.
    private let mounted = GravityVector(x: 0, y: -1, z: 0)
    /// Gravity after lifting the phone flat (face up): now along z.
    private let lifted = GravityVector(x: 0, y: 0, z: -1)

    @Test func firstSampleOnlySeedsTheReference() {
        var detector = PickupDetector()
        // The very first sample establishes the baseline and never fires.
        #expect(detector.update(gravity: mounted, timestamp: 0) == false)
    }

    @Test func smallJitterDoesNotFire() {
        var detector = PickupDetector()
        _ = detector.update(gravity: mounted, timestamp: 0)
        // A tiny tilt (well under the threshold) is mount jitter, not a pickup.
        let jitter = GravityVector(x: 0.05, y: -0.998, z: 0)
        #expect(detector.update(gravity: jitter, timestamp: 0.1) == false)
    }

    @Test func largeAttitudeChangeFiresOnce() {
        var detector = PickupDetector()
        _ = detector.update(gravity: mounted, timestamp: 0)
        // A 90° change (upright → flat) is well past the ~29° threshold.
        #expect(detector.update(gravity: lifted, timestamp: 0.2) == true)
    }

    @Test func debounceSuppressesRepeatWithinInterval() {
        var detector = PickupDetector(minInterval: 3)
        _ = detector.update(gravity: mounted, timestamp: 0)
        #expect(detector.update(gravity: lifted, timestamp: 0.2) == true)
        // Still held / lifted again within the debounce window ⇒ no re-fire.
        #expect(detector.update(gravity: lifted, timestamp: 1.0) == false)
        #expect(detector.update(gravity: lifted, timestamp: 2.9) == false)
    }

    @Test func settlingRebaselinesSoANewLiftIsDetected() {
        var detector = PickupDetector(minInterval: 1)
        _ = detector.update(gravity: mounted, timestamp: 0)
        #expect(detector.update(gravity: lifted, timestamp: 0.2) == true)

        // The phone settles into the new (flat) pose: the reference re-baselines.
        #expect(detector.update(gravity: lifted, timestamp: 1.5) == false)

        // Lifting again from the new resting pose, past the debounce ⇒ fires.
        #expect(detector.update(gravity: mounted, timestamp: 3.0) == true)
    }

    @Test func angleBetweenIsPi2ForOrthogonalVectors() {
        let angle = PickupDetector.angleBetween(mounted, lifted)
        #expect(abs(angle - (.pi / 2)) < 0.001)
    }

    @Test func resetClearsBaselineAndDebounce() {
        var detector = PickupDetector()
        _ = detector.update(gravity: mounted, timestamp: 0)
        #expect(detector.update(gravity: lifted, timestamp: 0.2) == true)
        detector.reset()
        // After reset the next sample only re-seeds the baseline.
        #expect(detector.update(gravity: lifted, timestamp: 0.3) == false)
    }
}
