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
    /// Count of near-miss events recorded during this ride (rear-camera Req 15,
    /// task 28). Shown as a small amber badge when non-zero. 0 by default so
    /// existing callers are unaffected.
    var nearMissCount: Int = 0

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RouteGlyph(points: ride.points)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(Self.titleText(for: ride.startedAt))
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if ride.isDemo {
                        demoTag
                    }
                }
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.sm) {
                if nearMissCount > 0 {
                    nearMissBadge
                }
                if showsSharing {
                    Image(systemName: sharingVariant.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                Image(systemName: syncVariant.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(syncIconColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Content

    /// Maps the ride's stored `syncStatus` to the chip variant (icon + text).
    private var syncVariant: StateChip.Variant {
        switch ride.syncStatus {
        case .localOnly: return .onDevice
        case .pending: return .pending
        case .synced: return .synced
        case .failed: return .failed
        }
    }

    private var sharingState: SharingState {
        SharingState.forRide(sharePublicly: ride.sharePublicly, syncStatus: ride.syncStatus)
    }

    /// Only surface a sharing icon when the ride is (or wants to be) public;
    /// a `.private` ride just shows its sync status.
    private var showsSharing: Bool { sharingState != .private }

    private var sharingVariant: StateChip.Variant {
        switch sharingState {
        case .private: return .privateRide
        case .shared: return .shared
        case .sharingPending: return .sharingPending
        }
    }

    private var syncIconColor: Color {
        switch ride.syncStatus {
        case .failed: return Theme.Palette.alert
        default: return Theme.Colors.textSecondary
        }
    }

    /// A small "Demo ride" tag (icon + text) so a simulated/seeded ride is never
    /// confused with a real one (demo-mode Requirement 2.3).
    private var demoTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Demo ride")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Theme.Palette.ink)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Theme.Palette.amber)
        .clipShape(Capsule())
    }

    /// A small amber near-miss count badge (experimental logged events, task 28).
    private var nearMissBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(nearMissCount)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Theme.Palette.ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.Palette.amber)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

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
        let demo = ride.isDemo ? "Demo ride, " : ""
        var text = "\(demo)\(Self.titleText(for: ride.startedAt)), \(subtitle), \(syncVariant.title)"
        if showsSharing {
            text += ", \(sharingState.title)"
        }
        if nearMissCount > 0 {
            let label = nearMissCount == 1 ? "1 near miss" : "\(nearMissCount) near misses"
            text += ", \(label)"
        }
        return text
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
