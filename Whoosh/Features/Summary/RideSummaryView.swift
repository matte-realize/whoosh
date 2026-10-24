import SwiftUI

/// The ride-summary screen (Requirement 6, mockup 4). Light app chrome.
///
/// Shown after a ride finishes ("Ride complete" title + a "Done" button that
/// dismisses back to Home) and **reused** as the history detail for a past ride
/// (the ride's date as the title, dismissed with the navigation back control —
/// no "Done" button). Renders a static full-route `RouteMapView`, a big
/// DISTANCE tile, RIDE TIME and AVG SPEED tiles (all via `Formatters`), and a
/// sync-status row (icon + text; `.localOnly` → "On device" until sync ships).
///
/// Handles 0/1-point rides without NaN or crashing: the summary numbers come
/// from the ride's finalized summary (zeroed for empty rides), and the map shows
/// a friendly "No route recorded" placeholder when there is nothing to draw.
///
/// Per the layering table this view uses only the injected `Ride` value and the
/// `RouteMapView` wrapper; it imports no framework service types.
struct RideSummaryView: View {
    enum Presentation {
        /// Just-finished ride: "Ride complete" + a "Done" button.
        case justFinished
        /// Past ride from History: date title, dismissed via the nav back control.
        case historyDetail
    }

    let ride: Ride
    var presentation: Presentation = .justFinished
    /// Sync status for the row (everything is `.localOnly` until sync ships).
    var syncStatus: SyncStatus = .localOnly
    /// Called when "Done" is tapped (only used in `.justFinished`).
    var onDone: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                mapCard
                distanceTile
                HStack(spacing: Theme.Spacing.md) {
                    rideTimeTile
                    avgSpeedTile
                }
                syncRow
                if presentation == .justFinished {
                    PrimaryButton("Done") { onDone() }
                        .padding(.top, Theme.Spacing.sm)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle(presentation == .historyDetail ? titleText : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(titleText)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitleText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: String {
        switch presentation {
        case .justFinished: return "Ride complete"
        case .historyDetail: return RideRow.titleText(for: ride.startedAt)
        }
    }

    /// e.g. "Thu, Oct 22 · 5:48 – 6:15 PM" — the ride's date and time range.
    private var subtitleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        let day = formatter.string(from: ride.startedAt)
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")
        let startTime = formatter.string(from: ride.startedAt)
        guard let end = ride.endedAt else {
            return "\(day) · \(startTime)"
        }
        let endTime = formatter.string(from: end)
        return "\(day) · \(startTime) – \(endTime)"
    }

    // MARK: - Map

    @ViewBuilder private var mapCard: some View {
        if ride.points.isEmpty {
            noRoutePlaceholder
        } else {
            RouteMapView(points: ride.points, mode: .static)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private var noRoutePlaceholder: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "map")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No route recorded")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("This ride had no GPS points.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No route recorded. This ride had no GPS points.")
    }

    // MARK: - Tiles

    private var distanceTile: some View {
        VStack(alignment: .leading) {
            StatTile(
                label: "Distance",
                value: numberOnly(Formatters.miles(fromMeters: ride.summary.distanceMeters), unit: "mi"),
                unit: "mi",
                valueSize: 32
            )
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var rideTimeTile: some View {
        StatTile(
            label: "Ride time",
            value: Formatters.duration(ride.summary.activeDuration),
            valueSize: 22
        )
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var avgSpeedTile: some View {
        StatTile(
            label: "Avg speed",
            value: numberOnly(Formatters.mph(fromMetersPerSecond: ride.summary.averageSpeedMetersPerSecond), unit: "mph"),
            unit: "mph",
            valueSize: 22
        )
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: - Sync status row

    private var syncRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: syncVariant.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(syncStatus.title)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status, \(syncStatus.title)")
    }

    private var syncVariant: StateChip.Variant {
        switch syncStatus {
        case .localOnly: return .onDevice
        case .pending: return .pending
        case .synced: return .synced
        }
    }

    // MARK: - Helpers

    private func numberOnly(_ formatted: String, unit: String) -> String {
        formatted.replacingOccurrences(of: " \(unit)", with: "")
    }
}

#Preview("Ride complete") {
    NavigationStack {
        RideSummaryView(ride: PreviewSeed.summaryRide(), presentation: .justFinished)
    }
}

#Preview("History detail") {
    NavigationStack {
        RideSummaryView(ride: PreviewSeed.summaryRide(), presentation: .historyDetail)
    }
}

#Preview("No route") {
    NavigationStack {
        RideSummaryView(
            ride: Ride(startedAt: Date(), endedAt: Date().addingTimeInterval(5), points: [], summary: .zero),
            presentation: .justFinished
        )
    }
}
