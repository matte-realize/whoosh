import SwiftUI

/// The Home hub (Requirements 13 + 2), realizing mockups 1 (dashboard) and 6
/// (location denied). Light app chrome.
///
/// The dashboard shows the Whoosh wordmark with a lime underline accent, a
/// "Ready to ride?" greeting, a settings button (top right), a This-Week stats
/// card (big miles number, "3 rides · 1h 02m", a Mon–Sun 7-bar chart from
/// `WeeklyStatsCalculator`), a Recent rides list ("See all ›" + up to 3
/// `RideRow`s, finished rides only), an inert dashed "Rear vehicle detection"
/// placeholder card (never requests camera), a large lime Start Ride button in
/// the thumb zone, and a GPS status chip.
///
/// When authorization is denied/restricted/services-off the Start area is
/// replaced by the location-denied state: a slashed-location icon, "Location is
/// off", a plain explanation, the privacy reassurance, numbered Open-Settings
/// steps, a lime "Open Settings" deep link, and a secondary "View past rides".
///
/// Navigation is **not** built here: the view exposes closures so the
/// composition root (task 23) wires `NavigationStack` pushes and the ride cover.
struct HomeView: View {
    let viewModel: HomeViewModel

    var onStartRide: () -> Void = {}
    var onOpenHistory: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onSelectRide: (Ride) -> Void = { _ in }

    /// Used to deep-link to this app's Settings page (injected so previews/tests
    /// don't touch `UIApplication`).
    var openAppSettings: () -> Void = {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.screenBackground.ignoresSafeArea()

            if viewModel.showsDashboard {
                dashboard
            } else {
                LocationDeniedView(
                    onOpenSettings: openAppSettings,
                    onViewPastRides: onOpenHistory
                )
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                WeeklyStatsCard(stats: viewModel.weeklyStats)
                recentRidesSection
                rearDetectionPlaceholder
                startArea
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Wordmark()
                Text("Ready to ride?")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.cardSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Recent rides

    private var recentRidesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Recent rides")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button(action: onOpenHistory) {
                    Text("See all ›")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all rides")
            }

            if viewModel.hasNoRides {
                emptyRecentState
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(viewModel.recentRides) { ride in
                        Button {
                            onSelectRide(ride)
                        } label: {
                            RideRow(ride: ride)
                                .background(Theme.Colors.cardSurface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyRecentState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("No rides yet")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your first ride will show up here.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No rides yet. Your first ride will show up here.")
    }

    // MARK: - Rear-detection placeholder (inert; never requests camera)

    private var rearDetectionPlaceholder: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "car.rear")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rear vehicle detection")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Experimental · coming soon")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(
                    Theme.Colors.textSecondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rear vehicle detection, experimental, coming soon")
    }

    // MARK: - Start area

    private var startArea: some View {
        VStack(spacing: Theme.Spacing.md) {
            PrimaryButton("Start Ride", systemImage: "play.fill") {
                viewModel.requestLocationIfNeeded()
                onStartRide()
            }
            StateChip(variant: .gpsReady)
        }
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - Wordmark

/// The "whoosh" wordmark with a short lime underline accent (mockup 1).
private struct Wordmark: View {
    var body: some View {
        Text("whoosh")
            .font(.system(size: 27, weight: .heavy))
            .foregroundStyle(Theme.Colors.textPrimary)
            .overlay(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Theme.Palette.lime)
                    .frame(width: 22, height: 3.5)
                    .offset(x: 0, y: 4)
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Whoosh")
    }
}

#Preview("Home — with rides") {
    HomeView(viewModel: PreviewSeed.homeViewModel(seeded: true))
}

#Preview("Home — empty") {
    HomeView(viewModel: PreviewSeed.homeViewModel(seeded: false))
}

#Preview("Home — denied") {
    HomeView(viewModel: PreviewSeed.homeViewModel(seeded: true, status: .denied))
}
