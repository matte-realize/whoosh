import SwiftUI

/// The unmissable "DEMO MODE" badge shown while demo mode is on, conveying its
/// meaning with **icon + text**, never colour alone (demo-mode Requirement 2.1,
/// 2.2). It is mounted on Home, the active-ride cover, and the emergency/crash
/// screens, positioned so it does not obscure primary ride metrics or the
/// "I'm OK — Cancel" control, and it sits **below** the crash countdown takeover.
///
/// Tapping the badge opens the demo tools as a convenience (O-DM5); the badge is
/// otherwise non-destructive. The badge is a thin view: it reads
/// `DemoModeController.badgeVisible` and renders nothing when demo mode is off,
/// so with the toggle off it is absent from the view hierarchy (Requirement 2.6).
struct DemoBadge: View {
    /// Tint for the surrounding screen: the light app chrome or the dark ride
    /// screen.
    enum Scheme {
        case light
        case dark
    }

    var scheme: Scheme = .light
    /// Optional tap handler that opens the demo tools (O-DM5). When `nil` the
    /// badge is purely informational.
    var onTap: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 12, weight: .bold))
            Text("DEMO MODE")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(Theme.Palette.ink)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.amber)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Theme.Palette.ink.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 4, y: 1)

        Group {
            if let onTap {
                Button(action: onTap) { label }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the demo tools")
            } else {
                label
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demo mode on. Everything shown is simulated and nothing is sent or uploaded.")
    }
}

#Preview("DemoBadge — light") {
    DemoBadge(scheme: .light, onTap: {})
        .padding()
        .background(Theme.Colors.screenBackground)
}

#Preview("DemoBadge — dark ride") {
    DemoBadge(scheme: .dark, onTap: {})
        .padding()
        .background(Theme.Colors.rideBackground)
}
