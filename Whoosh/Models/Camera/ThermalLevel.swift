import Foundation

/// The device thermal level the camera subsystem reacts to (rear-camera spec
/// Requirement 12.1, design "ThermalPolicy"). Mirrors `ProcessInfo.ThermalState`
/// but stays in the Models layer (Foundation only) so pure policies and tests
/// never touch the framework type.
///
/// `Comparable` so step-up/step-down logic can order levels directly. The raw
/// `Int` also fixes the ordering for `Codable`.
///
/// Foundation-only enum; `Int`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`, `Comparable`.
enum ThermalLevel: Int, Equatable, Codable, Sendable, CaseIterable, Comparable {
    /// No thermal concern; the requested profile runs.
    case nominal = 0
    /// Mild warmth; the requested profile still runs.
    case fair = 1
    /// Step down frame rate, then resolution; cap consumers at half rate.
    case serious = 2
    /// Stop the camera (finalize); GPS continues; the rider is told.
    case critical = 3

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
