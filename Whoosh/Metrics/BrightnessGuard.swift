import Foundation

/// The pure brightness-restore decision helper for ride mode (rear-camera spec
/// Requirement 10.2, design "BrightnessGuard"). Given the dim guard (the rider's
/// original brightness and the dim value ride mode set), the current reading,
/// and whether a change was rider-initiated, it decides what to do without
/// touching `UIScreen`.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The
/// `RideModeController` / `UIKitScreenController` (task 21) performs the actual
/// write from the returned `BrightnessDecision`.
///
/// The design's six cases (BG-1…6):
/// 1. Normal restore — reading is still the dim value ⇒ `.restore(original)`.
/// 2. Rider changed brightness while unlocked ⇒ leave it (`.noChange`).
/// 3. Brightness already equals the original ⇒ `.noChange`.
/// 4. Guard persisted from a previous run ⇒ restore once (same as case 1).
/// 5. Repeated enter without exit ⇒ do not overwrite the stored original with
///    the dimmed value (`guardForEntering`).
/// 6. System/Auto-Brightness moved it while locked ⇒ re-apply the dim value.
enum BrightnessGuard {
    /// Brightness readings within this fraction are treated as equal (display
    /// brightness is quantised and never lands on an exact float).
    static let tolerance: Double = 0.001

    /// The restore target when leaving the dimmed state (unlock, resign active,
    /// ride end, or a launch-time guard). Returns `.noChange` if the screen is
    /// already at the rider's original value (BG-3), otherwise `.restore`
    /// (BG-1, BG-4).
    static func restoreTarget(
        guard guardState: BrightnessGuardState,
        currentReading: Double
    ) -> BrightnessDecision {
        if approximatelyEqual(currentReading, guardState.original) {
            return .noChange
        }
        return .restore(guardState.original)
    }

    /// The decision for an external brightness change while ride mode is running
    /// (design row 13). If the rider changed it deliberately while unlocked it is
    /// left alone (BG-2); otherwise, while locked, the dim value is re-applied
    /// (BG-6) unless the reading already matches it.
    static func decisionForExternalChange(
        guard guardState: BrightnessGuardState,
        currentReading: Double,
        riderInitiated: Bool
    ) -> BrightnessDecision {
        if riderInitiated {
            return .noChange
        }
        if approximatelyEqual(currentReading, guardState.dimmed) {
            return .noChange
        }
        return .reapplyDim(guardState.dimmed)
    }

    /// Build the guard to persist when entering the dimmed state. On the first
    /// entry (`existing == nil`) the current reading is the rider's real
    /// brightness and becomes the original. On a repeated entry without an
    /// intervening exit the existing original is preserved, so a dimmed reading
    /// can never overwrite it (BG-5).
    static func guardForEntering(
        existing: BrightnessGuardState?,
        currentReading: Double,
        dimTarget: Double
    ) -> BrightnessGuardState {
        if let existing {
            return BrightnessGuardState(original: existing.original, dimmed: dimTarget)
        }
        return BrightnessGuardState(original: currentReading, dimmed: dimTarget)
    }

    // MARK: - Private

    private static func approximatelyEqual(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= tolerance
    }
}
