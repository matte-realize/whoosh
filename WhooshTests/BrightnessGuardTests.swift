import Foundation
import Testing
@testable import Whoosh

/// Tests for the pure `BrightnessGuard` restore-target function (rear-camera
/// task 8, Requirement 10.2, design "BrightnessGuard"). The design lists six
/// cases (BG-1…6): normal restore, rider changed brightness while unlocked
/// (leave it), brightness already equals the original (no-op), a guard persisted
/// from a previous run (restore once), repeated enter without exit (do not
/// overwrite the original with the dimmed value), and re-applying the dim when
/// the system/Auto-Brightness moved it away while locked.
struct BrightnessGuardTests {
    private let tuning = RideCameraTuning() // dimBrightness = 0.0

    // MARK: BG-1 — normal restore: reading is still the dim value ⇒ restore original

    @Test func bg1_normalRestore() {
        let guardState = BrightnessGuardState(original: 0.8, dimmed: 0.0)
        let decision = BrightnessGuard.restoreTarget(guard: guardState, currentReading: 0.0)
        #expect(decision == .restore(0.8))
    }

    // MARK: BG-2 — rider changed brightness while unlocked ⇒ leave it

    @Test func bg2_riderChangedWhileUnlockedLeftAlone() {
        let guardState = BrightnessGuardState(original: 0.8, dimmed: 0.0)
        let decision = BrightnessGuard.decisionForExternalChange(
            guard: guardState,
            currentReading: 0.6,
            riderInitiated: true
        )
        #expect(decision == .noChange)
    }

    // MARK: BG-3 — brightness already equals the original ⇒ no-op

    @Test func bg3_alreadyEqualOriginalNoOp() {
        let guardState = BrightnessGuardState(original: 0.8, dimmed: 0.0)
        let decision = BrightnessGuard.restoreTarget(guard: guardState, currentReading: 0.8)
        #expect(decision == .noChange)
    }

    // MARK: BG-4 — guard persisted from a previous run ⇒ restore once

    @Test func bg4_persistedGuardRestoresOnce() {
        // On launch the live reading is whatever the previous run left (the dim
        // value); restoring brings it back to the saved original.
        let persisted = BrightnessGuardState(original: 0.65, dimmed: 0.0)
        let decision = BrightnessGuard.restoreTarget(guard: persisted, currentReading: 0.0)
        #expect(decision == .restore(0.65))
    }

    // MARK: BG-5 — repeated enter without exit ⇒ do not overwrite the original

    @Test func bg5_repeatedEnterKeepsOriginal() {
        // First entry: no existing guard, reading is the rider's real brightness.
        let first = BrightnessGuard.guardForEntering(
            existing: nil,
            currentReading: 0.8,
            dimTarget: tuning.dimBrightness
        )
        #expect(first == BrightnessGuardState(original: 0.8, dimmed: tuning.dimBrightness))

        // Second entry while already dimmed (no exit happened): the current
        // reading is now the dim value, but the original must be preserved.
        let second = BrightnessGuard.guardForEntering(
            existing: first,
            currentReading: 0.0,
            dimTarget: tuning.dimBrightness
        )
        #expect(second.original == 0.8)
        #expect(second.dimmed == tuning.dimBrightness)
    }

    // MARK: BG-6 — system moved brightness while locked ⇒ re-apply dim

    @Test func bg6_externalChangeWhileLockedReappliesDim() {
        let guardState = BrightnessGuardState(original: 0.8, dimmed: 0.0)
        let decision = BrightnessGuard.decisionForExternalChange(
            guard: guardState,
            currentReading: 0.7,
            riderInitiated: false
        )
        #expect(decision == .reapplyDim(0.0))
    }

    /// Extra: an external change while locked that is already at the dim value is
    /// a no-op (nothing to re-apply).
    @Test func bg6_externalChangeAlreadyDimNoOp() {
        let guardState = BrightnessGuardState(original: 0.8, dimmed: 0.0)
        let decision = BrightnessGuard.decisionForExternalChange(
            guard: guardState,
            currentReading: 0.0,
            riderInitiated: false
        )
        #expect(decision == .noChange)
    }
}
