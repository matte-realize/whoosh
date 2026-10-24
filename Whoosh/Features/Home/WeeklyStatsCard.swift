import SwiftUI

/// The This-Week stats card on Home (Requirement 13.2): a big total-miles
/// number, a "N rides · total active time" subtitle, and a Monday–Sunday 7-bar
/// chart of distance per weekday fed by `WeeklyStats`.
///
/// Numbers use tabular numerals via `StatTile`/`Formatters`. The chart carries a
/// single combined VoiceOver summary (never color alone) so the whole card is
/// legible to assistive tech. An empty week renders zeros and a flat chart
/// sensibly (Requirement 13.6).
struct WeeklyStatsCard: View {
    let stats: WeeklyStats

    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]
    private static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("THIS WEEK")
                    .font(Theme.Typography.sectionHeader)
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(milesValue)
                        .font(Theme.Typography.metric(30))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("mi")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            chart
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.largeCard))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    // MARK: - Chart

    private var chart: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: Theme.Spacing.xs) {
                    bar(for: index)
                    Text(Self.weekdayInitials[index])
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }

    private func bar(for index: Int) -> some View {
        let distance = stats.distancePerWeekday[index]
        let maxDistance = max(stats.distancePerWeekday.max() ?? 0, 1)
        let fraction = distance / maxDistance
        let hasRide = distance > 0
        let height = hasRide ? max(CGFloat(fraction) * 32, 6) : 3
        return RoundedRectangle(cornerRadius: 2)
            .fill(hasRide ? Theme.Palette.ink : Theme.Colors.separator)
            .frame(width: 8, height: height)
    }

    // MARK: - Formatting

    private var milesValue: String {
        // Reuse Formatters for the mi conversion, stripping the " mi" suffix so
        // the unit can render smaller beside the number (matching the mockup).
        let formatted = Formatters.miles(fromMeters: stats.totalDistanceMeters)
        return formatted.replacingOccurrences(of: " mi", with: "")
    }

    private var subtitle: String {
        let rideWord = stats.rideCount == 1 ? "ride" : "rides"
        let time = compactDuration(stats.totalActiveDuration)
        return "\(stats.rideCount) \(rideWord) · \(time)"
    }

    /// Compact "1h 02m" / "47m" style for the card subtitle (distinct from the
    /// ride-screen `m:ss` clock). Zero reads as "0m".
    private func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.towardZero))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 1 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return "\(minutes)m"
    }

    private var accessibilitySummary: String {
        let rideWord = stats.rideCount == 1 ? "ride" : "rides"
        var parts = [
            "This week: \(Formatters.miles(fromMeters: stats.totalDistanceMeters))",
            "\(stats.rideCount) \(rideWord)",
            "\(compactDuration(stats.totalActiveDuration)) active",
        ]
        // Per-day summary so the chart is legible to VoiceOver.
        let dayParts: [String] = (0..<7).compactMap { index in
            let distance = stats.distancePerWeekday[index]
            guard distance > 0 else { return nil }
            return "\(Self.weekdayNames[index]) \(Formatters.miles(fromMeters: distance))"
        }
        if dayParts.isEmpty {
            parts.append("No rides this week")
        } else {
            parts.append("By day: " + dayParts.joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }
}

#Preview("WeeklyStatsCard") {
    VStack(spacing: Theme.Spacing.lg) {
        WeeklyStatsCard(stats: WeeklyStats(
            totalDistanceMeters: 19_955,
            rideCount: 3,
            totalActiveDuration: 3_720,
            distancePerWeekday: [0, 5_200, 0, 9_500, 5_255, 0, 0]
        ))
        WeeklyStatsCard(stats: .empty)
    }
    .padding()
    .background(Theme.Colors.screenBackground)
}
