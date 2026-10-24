import Foundation

/// The kind of a wire alert (watch-companion design "`WireAlert`";
/// Requirement 11.1). An unknown kind plays the generic notice pattern with the
/// text "Whoosh notice" (Requirement 5.4). `patternPreview` carries a pattern
/// name as a short code (not free text).
public enum WireAlertKind: String, Codable, Equatable, Sendable, CaseIterable {
    case rearVehicleCaution
    case cameraInterrupted
    case cameraResumed
    case cameraStopped
    case clipSaved
    case clipNotSaved
    case phoneBatteryLow
    case crashCountdownStarted
    case crashCountdownEnded
    case hapticTest
    case patternPreview
    case linkRestored
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WireAlertKind(rawValue: raw) ?? .unknown
    }
}
