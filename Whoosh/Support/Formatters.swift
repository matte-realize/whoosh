import Foundation

/// Centralized SI → US customary formatting (Requirements 10.1/10.2). This is
/// the only place SI storage units are converted for display, so unit policy
/// lives in one tested location.
///
/// Output is locale-independent (fixed en_US) so tests are deterministic
/// regardless of the host locale.
enum Formatters {
    // MARK: Unit conversion constants

    private static let metersPerMile: Double = 1_609.344
    private static let feetPerMeter: Double = 3.280_839_895
    /// 1 m/s in mph.
    private static let mphPerMetersPerSecond: Double = 2.236_936_292

    /// Short distances below this many miles are shown in feet (Requirement 10.1).
    private static let feetThresholdMiles: Double = 0.1
    /// At or above this many miles, distance uses one decimal instead of two.
    private static let milesDecimalSwitch: Double = 10

    private static let enUS = Locale(identifier: "en_US")

    // MARK: Distance

    /// Distance in miles: two decimals under 10 mi, one decimal at or above 10 mi.
    /// Zero formats as "0.00 mi".
    static func miles(fromMeters meters: Double) -> String {
        let miles = max(0, meters) / metersPerMile
        let fractionDigits = miles >= milesDecimalSwitch ? 1 : 2
        return "\(decimal(miles, fractionDigits: fractionDigits)) mi"
    }

    /// Feet, rounded to a whole number, e.g. "320 ft". For very short distances.
    static func feet(fromMeters meters: Double) -> String {
        let feet = max(0, meters) * feetPerMeter
        return "\(decimal(feet, fractionDigits: 0)) ft"
    }

    /// Distance formatted for display where short distances are shown in feet:
    /// under 0.1 mi → feet; otherwise miles with the usual decimal policy.
    static func shortDistance(fromMeters meters: Double) -> String {
        let clamped = max(0, meters)
        let miles = clamped / metersPerMile
        if miles < feetThresholdMiles {
            return feet(fromMeters: clamped)
        }
        return self.miles(fromMeters: clamped)
    }

    // MARK: Speed

    /// Speed in mph with one decimal, e.g. "0.0 mph", "15.3 mph". Negative
    /// (unknown) speeds clamp to zero.
    static func mph(fromMetersPerSecond speed: Double) -> String {
        let mph = max(0, speed) * mphPerMetersPerSecond
        return "\(decimal(mph, fractionDigits: 1)) mph"
    }

    // MARK: Duration

    /// Human-readable duration: `m:ss` under an hour, `h:mm:ss` at or above an
    /// hour. Zero formats as "0:00". Negative inputs clamp to zero.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.towardZero))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours >= 1 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Helpers

    /// Fixed en_US decimal formatting with the given fraction digits (grouping
    /// separators on, e.g. "1,234"), so output never varies by host locale.
    private static func decimal(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = enUS
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        let number = NSNumber(value: value)
        return formatter.string(from: number) ?? String(format: "%.\(fractionDigits)f", value)
    }
}
