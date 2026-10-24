import SwiftUI

/// The Settings screen (Requirement 14), realizing mockup 7. Pushed from Home on
/// the `NavigationStack` with a "Home" back label (the composition root, task 23,
/// owns the stack; this view just sets its title and back behavior).
///
/// Sections:
/// - **CLOUD SYNC** — a DISABLED "Sync rides to Whoosh map" toggle with a
///   plain-language explanation of exactly what is uploaded (and that camera
///   video is never uploaded), plus "Coming soon" Privacy zone / Identity rows.
///   These stay disabled until the sync tasks ship (Requirement 14.5 / 12.1).
/// - **RIDE** — a read-only "Units · Miles · mph" row and a functional GPS
///   accuracy picker (Balanced / High) bound to `SettingsViewModel`.
/// - **SAFETY · EXPERIMENTAL** — a disabled "Rear vehicle detection · Soon" row
///   that never requests camera permission (Requirement 14.6).
/// - A destructive "Delete all rides" action behind a confirmation alert that
///   calls `SettingsViewModel.deleteAllRides()` and surfaces any error message.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showDeleteConfirmation = false

    /// Navigation hook to push the Emergency setup hub (crash-response task 16).
    /// Defaults to a no-op so the composition root (task 26) wires the push
    /// without this view depending on it; the row is hidden until it is wired.
    var onOpenCrashAlerts: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                cloudSyncSection
                rideSection
                crashAlertsSection
                safetySection
                deleteAllButton
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete all rides?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                viewModel.deleteAllRides()
            }
        } message: {
            Text("This permanently removes every ride stored on this iPhone. This can't be undone.")
        }
        .alert(
            "Couldn't delete rides",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
    }

    // MARK: - Cloud sync

    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Cloud sync")
            VStack(spacing: 0) {
                // Disabled sync toggle — "Coming soon" until sync ships.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync rides to Whoosh map")
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("Coming soon")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                        .disabled(true)
                        .tint(Theme.Palette.lime)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sync rides to Whoosh map, coming soon, off")

                rowDivider
                disabledValueRow(title: "Privacy zone", value: "0.1 mi")
                rowDivider
                disabledValueRow(title: "Identity", value: "Anonymous")
            }
            .cardStyle()

            Text("Uploads finished rides (stats + route) so they appear on the Whoosh website. Camera video is never uploaded. Off by default.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Ride

    private var rideSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Ride")
            VStack(spacing: 0) {
                // Units — read-only for the MVP.
                HStack {
                    Text("Units")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("Miles · mph")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Units, Miles and miles per hour")

                rowDivider

                // Functional GPS accuracy picker bound to the view model.
                HStack {
                    Text("GPS accuracy")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Picker("GPS accuracy", selection: $viewModel.accuracy) {
                        ForEach(TrackingAccuracy.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("GPS accuracy, \(viewModel.accuracy.rawValue)")
            }
            .cardStyle()
        }
    }

    // MARK: - Safety · Crash alerts (opt-in; pushes the Emergency setup hub)

    @ViewBuilder private var crashAlertsSection: some View {
        if let onOpenCrashAlerts {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Safety")
                Button(action: onOpenCrashAlerts) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Crash alerts")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Opt-in. Off by default.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardStyle()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Crash alerts, opt-in, off by default")
                .accessibilityHint("Opens emergency contact and crash alert setup")
            }
        }
    }

    // MARK: - Safety (experimental)

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Safety · Experimental")
            HStack {
                Text("Rear vehicle detection")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("Soon")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.subtleFill)
                    .clipShape(Capsule())
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rear vehicle detection, experimental, coming soon")
        }
    }

    // MARK: - Delete all

    private var deleteAllButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text("Delete all rides")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.alert)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete all rides")
        .accessibilityHint("Permanently removes every ride on this iPhone")
    }

    // MARK: - Row helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func disabledValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), coming soon")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.md)
    }
}

// MARK: - Card background modifier

private extension View {
    func cardStyle() -> some View {
        background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView(viewModel: SettingsViewModel(repository: InMemoryRideRepository()))
    }
}
