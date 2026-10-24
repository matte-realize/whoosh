import SwiftUI

/// A compact, collapsible floating demo menu for the active-ride screen
/// (demo-mode Requirement 3.2, 3.6). It offers the ride-time demo triggers —
/// simulate an approaching vehicle, simulate a crash (drill), and adjust the
/// simulated-ride playback speed — without obscuring the three ride metrics or
/// the hold-to-stop control.
///
/// It is a thin view over `DemoModeController`: every control calls an
/// already-tested controller intent. It collapses to a single small button so it
/// never blocks the "I'm OK — Cancel" takeover or hold-to-stop, and the caller
/// hides it entirely behind a crash countdown takeover (Crash Req 8.8). Targets
/// are ≥ 60 pt and VoiceOver-labelled (Requirement 3.5).
///
/// All copy is honest and experimental: the rear cue cannot guarantee detection
/// or delivery; the crash action is a drill.
struct RideScreenDemoMenu: View {
    @Bindable var controller: DemoModeController
    @State private var expanded = false

    /// Playback speed options: 1× plus the accelerated factors from `DemoTuning`.
    private let speedOptions: [Double] = [1] + DemoTuning().acceleratedSpeedFactors

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            if expanded {
                expandedControls
            }
            toggleButton
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    // MARK: - Collapsed toggle

    private var toggleButton: some View {
        Button {
            expanded.toggle()
        } label: {
            Image(systemName: expanded ? "xmark" : "wrench.and.screwdriver.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: Theme.Size.minTouchTarget, height: Theme.Size.minTouchTarget)
                .background(Theme.Palette.amber)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Close demo tools" : "Open demo tools")
    }

    // MARK: - Expanded controls

    private var expandedControls: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            menuButton(
                title: "Simulate vehicle",
                systemImage: "car.fill",
                hint: "Fires an experimental rear-vehicle cue"
            ) {
                controller.fireRearAlertOnce()
            }

            menuButton(
                title: "Simulate crash (drill)",
                systemImage: "exclamationmark.triangle.fill",
                hint: "Runs a crash drill — DEMO, not real; nothing is sent"
            ) {
                controller.simulateCrashDrill()
            }

            speedControl
        }
    }

    private var speedControl: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "speedometer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            ForEach(speedOptions, id: \.self) { factor in
                Button {
                    controller.setSimulatedSpeed(factor)
                } label: {
                    Text(speedLabel(factor))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected(factor) ? Theme.Palette.ink : .white)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(isSelected(factor) ? Theme.Palette.lime : Theme.Colors.rideChipFill.opacity(0.85))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.Colors.rideChipStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed \(speedLabel(factor))")
                .accessibilityAddTraits(isSelected(factor) ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.rideCard.opacity(0.9))
        .clipShape(Capsule())
    }

    private func menuButton(
        title: String,
        systemImage: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .background(Theme.Colors.rideCard.opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.Colors.rideChipStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func isSelected(_ factor: Double) -> Bool {
        abs(controller.simulatedSpeedFactor - factor) < 0.0001
    }

    private func speedLabel(_ factor: Double) -> String {
        factor == factor.rounded() ? "\(Int(factor))×" : "\(factor)×"
    }
}

#Preview("RideScreenDemoMenu") {
    let env = AppEnvironment.preview()
    env.demo.isEnabled = true
    return ZStack(alignment: .bottomTrailing) {
        Theme.Colors.rideBackground.ignoresSafeArea()
        RideScreenDemoMenu(controller: env.demo)
            .padding()
    }
}
