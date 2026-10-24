import SwiftUI

/// The non-blocking location-denied state on Home (Requirement 2.2 / 2.6),
/// realizing mockup 6. Shown instead of the Start area when authorization is
/// denied/restricted or location services are off device-wide.
///
/// Contents: a slashed-location icon, a "Location is off" title, a plain
/// explanation of why location is needed, the privacy reassurance ("Your
/// location stays on this iPhone unless you turn on ride sync."), a numbered
/// 1-2-3 Open-Settings help sequence, a lime "Open Settings" deep-link button,
/// and a secondary "View past rides" button so history stays reachable
/// (Requirement 2.3). The app never dead-ends here.
struct LocationDeniedView: View {
    let onOpenSettings: () -> Void
    let onViewPastRides: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                icon
                    .padding(.top, Theme.Spacing.xxl)

                VStack(spacing: Theme.Spacing.md) {
                    Text("Location is off")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Whoosh needs your location to record your route and draw your ride map.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Your location stays on this iPhone unless you turn on ride sync.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                steps

                VStack(spacing: Theme.Spacing.md) {
                    PrimaryButton("Open Settings", action: onOpenSettings)
                    PrimaryButton("View past rides", style: .secondary, action: onViewPastRides)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.cardSurface)
                .frame(width: 92, height: 92)
            Image(systemName: "location.slash.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityHidden(true)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            step(1, "Open Settings")
            step(2, "Tap Location")
            step(3, "Choose \u{201C}While Using the App\u{201D}")
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("To turn on location: 1. Open Settings. 2. Tap Location. 3. Choose While Using the App.")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 18, height: 18)
                .background(Theme.Colors.subtleFill)
                .clipShape(Circle())
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

#Preview("Location denied") {
    LocationDeniedView(onOpenSettings: {}, onViewPastRides: {})
        .background(Theme.Colors.screenBackground)
}
