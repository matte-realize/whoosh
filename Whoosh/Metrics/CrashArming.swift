import Foundation

/// Pure arming rule for the crash detector (spec Requirement 5.4, design
/// decision D24 / Owner resolution O10). Pure, framework-free (Metrics layer).
///
/// The detector is **armed** — allowed to emit a probable-crash signal that the
/// reducer will act on — only while ALL of these hold:
/// - the ride is `recording` or `signalLost` (disarmed while `paused`, `idle`,
///   or `finished`, per O10; handling the phone at a stop is a false-positive
///   source),
/// - crash alerts are enabled,
/// - consent is current (acknowledged and at/above the minimum version),
/// - a rider label is present,
/// - at least one `reachable` contact exists.
///
/// This is a function of its inputs only, so it is fully unit-tested as a truth
/// table and reused by the coordinator and the ride bridge.
enum CrashArming {
    /// The inputs that determine arming. A value type so callers snapshot the
    /// current app state and the result is deterministic.
    struct Input: Equatable, Sendable {
        let rideState: RideState
        let enabled: Bool
        let consentCurrent: Bool
        let riderLabelPresent: Bool
        let reachableContactCount: Int

        init(
            rideState: RideState,
            enabled: Bool,
            consentCurrent: Bool,
            riderLabelPresent: Bool,
            reachableContactCount: Int
        ) {
            self.rideState = rideState
            self.enabled = enabled
            self.consentCurrent = consentCurrent
            self.riderLabelPresent = riderLabelPresent
            self.reachableContactCount = reachableContactCount
        }
    }

    /// Whether the detector is armed for the given inputs.
    static func isArmed(_ input: Input) -> Bool {
        isArmedRideState(input.rideState)
            && input.enabled
            && input.consentCurrent
            && input.riderLabelPresent
            && input.reachableContactCount >= 1
    }

    /// Only `recording` and `signalLost` arm the detector (O10).
    private static func isArmedRideState(_ state: RideState) -> Bool {
        switch state {
        case .recording, .signalLost:
            return true
        case .idle, .paused, .finished:
            return false
        }
    }
}
