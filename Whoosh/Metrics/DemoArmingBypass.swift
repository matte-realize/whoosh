import Foundation

/// Pure arming-bypass rule for demo-mode crash **drills** (demo-mode task 4,
/// Requirement 6.3). Pure, framework-free (Metrics layer).
///
/// A crash **drill** (the "Simulate crash" demo path) must run the real
/// countdown takeover even when the normal `CrashArming` preconditions are not
/// met — there may be no active ride, no consent, and no reachable contact. So
/// for a drill signal the bypass reports "armed" regardless of `CrashArming`.
///
/// A **real** (non-drill) signal is never affected: it still obeys
/// `CrashArming` exactly as the crash spec defines. This keeps the safety
/// invariant that demo mode can never send a real alert — the only thing the
/// bypass unlocks is the drill, which uses the `drill` template and (in Tier 0)
/// the composer fallback, never an automatic real send.
enum DemoArmingBypass {
    /// Whether the reducer should treat this signal as armed.
    ///
    /// - Parameters:
    ///   - isDrill: `true` for the demo "Simulate crash" path.
    ///   - normallyArmed: the ordinary `CrashArming.isArmed(...)` result.
    ///   - demoModeEnabled: whether demo mode is currently on (the bypass only
    ///     applies while demo mode is enabled, so production arming is untouched).
    /// - Returns: `true` when the signal should be acted on.
    static func isArmed(isDrill: Bool, normallyArmed: Bool, demoModeEnabled: Bool) -> Bool {
        if isDrill, demoModeEnabled {
            // Drills bypass arming in demo mode only.
            return true
        }
        // Real signals (and any signal outside demo mode) obey normal arming.
        return normallyArmed
    }
}
