import SwiftUI

/// A preview-only gallery that renders every design-system component together so
/// the team can eyeball the theme in both light and dark mode (Requirement 15
/// "Verify"). Not part of the app's navigation — it exists purely for `#Preview`.
struct ComponentGallery: View {
    private static let sampleRide: Ride = {
        let base = Date(timeIntervalSince1970: 1_729_630_080) // Thu, Oct 22
        let points: [RoutePoint] = (0..<10).map { i in
            let lat: Double = 42.36 + Double(i) * 0.001 + (i % 3 == 0 ? 0.0006 : 0)
            let lon: Double = -71.09 + Double(i) * 0.0012
            let time = base.addingTimeInterval(Double(i) * 10)
            return RoutePoint(
                latitude: lat,
                longitude: lon,
                timestamp: time,
                speedMetersPerSecond: 5.8,
                horizontalAccuracyMeters: 5
            )
        }
        return Ride(
            startedAt: base,
            endedAt: base.addingTimeInterval(1458),
            points: points,
            summary: RideSummary(
                distanceMeters: 8561,
                activeDuration: 1458,
                averageSpeedMetersPerSecond: 5.87
            )
        )
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                section("Buttons") {
                    PrimaryButton("Start Ride", systemImage: "play.fill") {}
                    PrimaryButton("View past rides", style: .secondary) {}
                }

                section("State chips") {
                    FlowChips(chips: [
                        StateChip(variant: .gpsReady),
                        StateChip(variant: .synced),
                        StateChip(variant: .pending),
                        StateChip(variant: .onDevice),
                        StateChip(variant: .signalLost),
                    ])
                }

                section("Stat tiles") {
                    HStack(spacing: Theme.Spacing.md) {
                        StatTile(label: "This week", value: "12.4", unit: "mi")
                        StatTile(label: "Rides", value: "3")
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                }

                section("Ride rows") {
                    VStack(spacing: 0) {
                        RideRow(ride: Self.sampleRide)
                        RideRow(ride: Self.sampleRide, showSpeed: false)
                    }
                    .background(Theme.Colors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                }

                section("Route glyphs") {
                    HStack(spacing: Theme.Spacing.md) {
                        RouteGlyph(points: Self.sampleRide.points)
                        RouteGlyph(points: [])
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title.uppercased())
                .font(Theme.Typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
    }
}

/// A simple wrapping row of chips for the gallery.
private struct FlowChips: View {
    let chips: [StateChip]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                chip
            }
        }
    }
}

#Preview("Gallery — light") {
    ComponentGallery()
        .preferredColorScheme(.light)
}

#Preview("Gallery — dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}
