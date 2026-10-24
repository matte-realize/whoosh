import SwiftUI

/// The "Demo mode" section for the Settings screen (demo-mode Requirement 1.1,
/// 1.3, 1.5, 1.7; task 10). It is its own section, separate from the other
/// Settings rows, with a single OFF-by-default toggle, a plain-language
/// explanation, an optional one-tap enable confirmation (O-DM4), and — while on
/// — the demo tools panel (`DemoToolsView`, task 11).
///
/// Thin view over `DemoModeController`: the toggle binds to `isEnabled` through
/// a confirmation gate; state is conveyed with icon + text, never colour alone
/// (Requirement 1.7). While demo mode is off the tools do not exist in the view
/// hierarchy (Requirement 3.3).
struct DemoModeSection: View {
    @Bindable var controller: DemoModeController
    @State private var showEnableConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Demo mode")

            VStack(spacing: 0) {
                toggleRow
            }
            .cardStyle()

            Text("Shows simulated rides and alerts for demonstrations. Nothing shown is real: no ride uses your GPS, nothing is sent to a contact, and nothing is uploaded. Off by default.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The tools only exist in the hierarchy while demo mode is on.
            if controller.isEnabled {
                DemoToolsView(controller: controller)
            }
        }
        .alert("Turn on Demo mode?", isPresented: $showEnableConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Turn on") { controller.isEnabled = true }
        } message: {
            Text("Rides and alerts shown will be simulated, labelled DEMO, and never sent or uploaded.")
        }
    }

    // MARK: - Toggle row

    private var toggleRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: controller.isEnabled ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(controller.isEnabled ? Theme.Palette.amber : Theme.Colors.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo mode")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(controller.isEnabled ? "On — simulated, nothing is sent" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: toggleBinding)
                .labelsHidden()
                .tint(Theme.Palette.amber)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo mode, \(controller.isEnabled ? "on" : "off")")
        .accessibilityHint("Shows simulated rides and alerts; nothing is real or uploaded")
    }

    /// Enabling routes through the optional one-tap confirmation (O-DM4);
    /// disabling is immediate.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { controller.isEnabled },
            set: { newValue in
                if newValue {
                    showEnableConfirmation = true
                } else {
                    controller.isEnabled = false
                }
            }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

private extension View {
    func cardStyle() -> some View {
        background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview("DemoModeSection — off") {
    let env = AppEnvironment.preview()
    return ScrollView {
        DemoModeSection(controller: env.demo)
            .padding()
    }
    .background(Theme.Colors.screenBackground)
}

#Preview("DemoModeSection — on") {
    let env = AppEnvironment.preview()
    env.demo.isEnabled = true
    return ScrollView {
        DemoModeSection(controller: env.demo)
            .padding()
    }
    .background(Theme.Colors.screenBackground)
}
