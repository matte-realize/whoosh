import Foundation

/// Formatting for the watch's three numbers (watch-companion design "Ride page":
/// elapsed time, distance in miles, speed in mph). The wire carries SI-ish
/// rounded integers (`distance10m` in 10 m units, `speedDms` in 0.1 m/s);
/// conversion to US customary happens only here (tech steering: SI internally,
/// US in the formatting layer).
enum WatchFormat {
    /// Elapsed time as `H:MM:SS` (or `M:SS` under an hour), from milliseconds.
    static func elapsed(_ ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1_000
        let h = totalSeconds / 3_600
        let m = (totalSeconds % 3_600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Distance in miles with one decimal, from 10 m units.
    static func miles(_ distance10m: Int) -> String {
        let meters = Double(max(0, distance10m)) * 10.0
        let miles = meters / 1_609.344
        return String(format: "%.1f", miles)
    }

    /// Speed in mph (whole number), from 0.1 m/s units. `nil` → "--".
    static func mph(_ speedDms: Int?) -> String {
        guard let speedDms, speedDms >= 0 else { return "--" }
        let mps = Double(speedDms) / 10.0
        let mph = mps * 2.2369362921
        return String(format: "%.0f", mph)
    }
}
