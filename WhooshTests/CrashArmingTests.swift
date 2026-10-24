import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `CrashArming` truth table (crash-response task 5,
/// Requirements 5.4, 7.2; design decision D24 / Owner resolution O10). Written
/// test-first.
///
/// The detector is **armed** only when ALL are true:
/// - the ride is `recording` or `signalLost` (disarmed while `paused`/`idle`/`finished`, O10),
/// - the feature is enabled,
/// - consent is current (acknowledged + version ≥ minimum),
/// - a rider label is present,
/// - at least one `reachable` contact exists.
struct CrashArmingTests {
    /// A fully-armed baseline input; each test flips one field.
    private func armedInput(
        rideState: RideState = .recording,
        enabled: Bool = true,
        consentCurrent: Bool = true,
        riderLabelPresent: Bool = true,
        reachableContactCount: Int = 1
    ) -> CrashArming.Input {
        CrashArming.Input(
            rideState: rideState,
            enabled: enabled,
            consentCurrent: consentCurrent,
            riderLabelPresent: riderLabelPresent,
            reachableContactCount: reachableContactCount
        )
    }

    // MARK: armed cases

    @Test func armedWhileRecording() {
        #expect(CrashArming.isArmed(armedInput(rideState: .recording)))
    }

    @Test func armedWhileSignalLost() {
        #expect(CrashArming.isArmed(armedInput(rideState: .signalLost)))
    }

    @Test func armedWithMultipleReachableContacts() {
        #expect(CrashArming.isArmed(armedInput(reachableContactCount: 3)))
    }

    // MARK: ride-state disarming (O10)

    @Test func disarmedWhilePaused() {
        #expect(!CrashArming.isArmed(armedInput(rideState: .paused)))
    }

    @Test func disarmedWhileIdle() {
        #expect(!CrashArming.isArmed(armedInput(rideState: .idle)))
    }

    @Test func disarmedWhileFinished() {
        #expect(!CrashArming.isArmed(armedInput(rideState: .finished)))
    }

    // MARK: feature / consent / label / contacts

    @Test func disarmedWhenFeatureOff() {
        #expect(!CrashArming.isArmed(armedInput(enabled: false)))
    }

    @Test func disarmedWhenConsentNotCurrent() {
        #expect(!CrashArming.isArmed(armedInput(consentCurrent: false)))
    }

    @Test func disarmedWhenRiderLabelMissing() {
        #expect(!CrashArming.isArmed(armedInput(riderLabelPresent: false)))
    }

    @Test func disarmedWhenNoReachableContact() {
        #expect(!CrashArming.isArmed(armedInput(reachableContactCount: 0)))
    }

    // MARK: full truth table (all combinations of the five boolean-ish inputs)

    @Test func fullTruthTable() {
        let activeRideStates: [RideState] = [.recording, .signalLost]
        let inactiveRideStates: [RideState] = [.idle, .paused, .finished]
        for rideState in RideState.allCasesForTest {
            for enabled in [true, false] {
                for consent in [true, false] {
                    for label in [true, false] {
                        for contacts in [0, 1, 2] {
                            let input = armedInput(
                                rideState: rideState,
                                enabled: enabled,
                                consentCurrent: consent,
                                riderLabelPresent: label,
                                reachableContactCount: contacts
                            )
                            let expected = activeRideStates.contains(rideState)
                                && enabled && consent && label && contacts >= 1
                            #expect(CrashArming.isArmed(input) == expected)
                            // sanity: inactive states are never armed
                            if inactiveRideStates.contains(rideState) {
                                #expect(!CrashArming.isArmed(input))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// `RideState` is `Equatable` but not `CaseIterable` in the app (it is pure and
/// has no raw value); this test-only helper enumerates its cases.
extension RideState {
    static var allCasesForTest: [RideState] {
        [.idle, .recording, .paused, .signalLost, .finished]
    }
}
