import Foundation

/// The persisted "dim guard": a record that ride mode lowered the screen
/// brightness and the rider's original value must be restored, even if the app
/// is killed or crashes while dimmed (rear-camera spec Requirement 10.2, design
/// "BrightnessGuard"). Written when ride mode dims (row 2) and cleared on every
/// restore path (rows 8, 12, 14).
///
/// Foundation-only value type (Models layer): `Equatable`, `Codable` (persisted
/// in `DimGuardStore`, task 21), `Sendable`. Brightness values are 0...1.
struct BrightnessGuardState: Equatable, Codable, Sendable {
    /// The rider's brightness before ride mode dimmed the screen; the value to
    /// restore.
    var original: Double
    /// The value ride mode set the screen to (the dim target, typically 0.0).
    /// Used to tell "our" change from a rider/Auto-Brightness change.
    var dimmed: Double

    init(original: Double, dimmed: Double) {
        self.original = original
        self.dimmed = dimmed
    }
}

/// What `BrightnessGuard` decided to do about the screen brightness. Returned as
/// data so the controller (task 21) performs the actual write. Foundation-only;
/// `Equatable`, `Sendable`.
enum BrightnessDecision: Equatable, Sendable {
    /// Restore the screen to this value (the stored original).
    case restore(Double)
    /// Re-apply the dim target (someone/Auto-Brightness moved it away while
    /// locked); value is the dim brightness to set.
    case reapplyDim(Double)
    /// Do nothing: the brightness already matches the intended value, or the
    /// rider deliberately changed it while unlocked and it should be left alone.
    case noChange
}
