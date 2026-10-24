import SwiftUI
import WhooshWire

/// Placeholder screen for the task 3 watch scaffold. It imports `WhooshWire`
/// so the project wiring that links the shared Foundation-only package into the
/// watch target is proven at build time. The real Ride / Controls / Idle /
/// Notices / Countdown / Summary / Settings pages arrive in watch-companion
/// tasks 20–21.
///
/// Honest copy only (the rear-vehicle cue is experimental; Whoosh cannot
/// guarantee detection or delivery) — enforced by `scripts/privacy-check.sh`.
struct WatchPlaceholderView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Whoosh")
                .font(.headline)
            Text("Wrist companion")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Setup pending")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        // Touch the shared module so the package link is exercised.
        .accessibilityIdentifier(WhooshWire.name)
    }
}

#Preview {
    WatchPlaceholderView()
}
