import SwiftUI

/// A single ride row for the Home "Recent rides" list and the History list
/// (Requirement 15.3). Shows the `RouteGlyph` thumbnail, a date/time title, a
/// "distance · duration · speed" subtitle built from centralized `Formatters`,
/// and a trailing sync-status indicator (icon + text, never color alone).
///
/// `showSpeed` lets History hide the average speed (the mockup's History rows
/// show "distance · duration" only, while Home's Recent rows add speed).
struct RideRow: View {
    let ride: Ride
    var showSpeed: Bool = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RouteGlyph(points: ride.points)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Self.titleText(for: ride.startedAt))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: syncVariant.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(syncIconColor)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Content

    /// Until cloud sync exists every ride reads "On device" (Requirement 6.6 /
    /// 7.2). Once sync ships this can map from the ride's stored sync status.
    private var syncVariant: StateChip.Variant { .onDevice }

    private var syncIconColor: Color { Theme.Colors.textSecondary }

    private var subtitle: String {
        var parts = [
            Formatters.miles(fromMeters: ride.summary.distanceMeters),
            Formatters.duration(ride.summary.activeDuration),
        ]
        if showSpeed {
            parts.append(Formatters.mph(fromMetersPerSecond: ride.summary.averageSpeedMetersPerSecond))
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        "\(Self.titleText(for: ride.startedAt)), \(subtitle), \(syncVariant.title)"
    }

    /// e.g. "Thu, Oct 22 · 5:48 PM" — fixed en_US so it matches the mockup and
    /// stays deterministic regardless of host locale.
    static func titleText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        let day = formatter.string(from: date)
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")
        let time = formatter.string(from: date)
        return "\(day) · \(time)"
    }
}

#Preview("RideRow") {
    let base = Date()
    let points: [RoutePoint] = (0..<6).map { i in
        let lat: Double = 42.36 + Double(i) * 0.001
        let lon: Double = -71.09 + Double(i) * 0.0012
        let time = base.addingTimeInterval(Double(i) * 10)
        return RoutePoint(
            latitude: lat,
            longitude: lon,
            timestamp: time,
            speedMetersPerSecond: 5,
            horizontalAccuracyMeters: 5
        )
    }
    let ride = Ride(
        startedAt: base,
        endedAt: base.addingTimeInterval(1458),
        points: points,
        summary: RideSummary(
            distanceMeters: 8561,
            activeDuration: 1458,
            averageSpeedMetersPerSecond: 5.87
        )
    )
    return VStack(spacing: Theme.Spacing.sm) {
        RideRow(ride: ride)
        RideRow(ride: ride, showSpeed: false)
    }
    .background(Theme.Colors.cardSurface)
    .padding()
    .background(Theme.Colors.screenBackground)
}
