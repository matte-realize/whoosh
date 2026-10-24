import Foundation

/// Pure free-space policy for the camera subsystem (rear-camera spec
/// Requirement 12.2, design "StoragePolicy"). Maps the free space available for
/// important usage to a `StorageStatus` and computes the **effective ring cap**
/// that shrinks before the stop floor is reached.
///
/// Pure, framework-free (Metrics layer: Models + Foundation only). The caller
/// supplies the free-space measure (from
/// `URLResourceValues.volumeAvailableCapacityForImportantUsage`, behind a
/// protocol); this type never touches the file system.
///
/// ## Rules (design table)
/// - free ≥ start min ⇒ `.ok`; recording and auto-pins allowed.
/// - free < warn ⇒ `.warn`; cap the ring at 50% and refuse auto-pins.
/// - free < stop floor ⇒ `.stop`; stop the camera (GPS continues).
/// - The "start" guard refuses to *start* the camera below the start minimum;
///   the "stop" floor stops an already-running camera.
enum StoragePolicy {
    /// The free-space status for the given free bytes.
    static func status(freeBytes: Int64, tuning: RideCameraTuning = RideCameraTuning()) -> StorageStatus {
        if freeBytes < tuning.freeSpaceStop {
            return .stop
        }
        if freeBytes < tuning.freeSpaceWarn {
            return .warn
        }
        return .ok
    }

    /// Whether the camera may **start** given the free space: only at or above
    /// the start minimum (design row: "refuse to start below a start minimum").
    static func canStart(freeBytes: Int64, tuning: RideCameraTuning = RideCameraTuning()) -> Bool {
        freeBytes >= tuning.freeSpaceStart
    }

    /// Whether auto-pins (detection clips) are allowed. Refused at `.warn` or
    /// `.stop` (design: "cap the ring at 50% and refuse auto-pins").
    static func allowsAutoPins(freeBytes: Int64, tuning: RideCameraTuning = RideCameraTuning()) -> Bool {
        status(freeBytes: freeBytes, tuning: tuning) == .ok
    }

    /// The effective ring byte cap for the current free space. At `.ok` the full
    /// configured cap; at `.warn` the cap is halved (shrink before the floor);
    /// at `.stop` zero (the camera is stopping, nothing new is kept).
    static func effectiveRingCap(freeBytes: Int64, tuning: RideCameraTuning = RideCameraTuning()) -> Int64 {
        switch status(freeBytes: freeBytes, tuning: tuning) {
        case .ok:
            return tuning.ringMaxBytes
        case .warn:
            return tuning.ringMaxBytes / 2
        case .stop:
            return 0
        }
    }
}
