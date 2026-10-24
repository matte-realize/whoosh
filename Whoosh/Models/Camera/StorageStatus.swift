import Foundation

/// Free-space status that gates recording and pinning (rear-camera spec
/// Requirement 12.2, design "StoragePolicy"). Derived from the important-usage
/// free-space measure against the start/warn/stop thresholds in
/// `RideCameraTuning`.
///
/// Foundation-only enum; `String`-backed `Codable`, `Equatable`, `Sendable`,
/// `CaseIterable`.
enum StorageStatus: String, Equatable, Codable, Sendable, CaseIterable {
    /// Free space ≥ the start minimum; recording and auto-pins allowed.
    case ok
    /// Below the warn threshold; cap the ring and refuse auto-pins.
    case warn
    /// Below the stop floor; stop the camera (GPS continues).
    case stop
}
