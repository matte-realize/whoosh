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
/// - **REAR CAMERA** — the real, opt-in "Record rear camera" section
///   (`RearCameraSettingsSection`), off by default; enabling it requests camera
///   access and turns on recording + experimental rear detection (Requirement
///   2/18.1). Recording is for the rider's own records and cannot guarantee
///   detection or delivery.
/// - A destructive "Delete all rides" action behind a confirmation alert that
///   calls `SettingsViewModel.deleteAllRides()` and surfaces any error message.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    /// Drives the "Rear camera" section and its first-enable permission flow
    /// (rear-camera spec Requirement 2/18.1, task 20).
    var rearCamera: RearCameraSettingsViewModel
    /// Demo mode's controller, so Settings can show the off-by-default "Demo
    /// mode" section and its tools (demo-mode Requirement 1.1).
    var demo: DemoModeController
    /// Drives the "Apple Watch" screen pushed from the watch row (watch-
    /// companion task 22). The view just pushes `WatchReadinessView`.
    var watchReadiness: WatchReadinessViewModel
    @State private var showDeleteConfirmation = false
    @Environment(\.openURL) private var openURL

    /// Navigation hook to push the Emergency setup hub (crash-response task 16).
    /// Defaults to a no-op so the composition root (task 26) wires the push
    /// without this view depending on it; the row is hidden until it is wired.
    var onOpenCrashAlerts: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                cloudSyncSection
                rideSection
                RearCameraSettingsSection(viewModel: rearCamera)
                appleWatchSection
                crashAlertsSection
                DemoModeSection(controller: demo)
                deleteAllButton
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        // Wire the rear-camera "Open Settings" path to the system Settings app
        // (the view model stays UIKit-free; the view owns the URL open).
        .onAppear {
            rearCamera.onOpenSystemSettings = {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
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
                // Functional sync toggle (off by default).
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync rides to Whoosh map")
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.syncEnabled },
                        set: { viewModel.setSyncEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.Palette.lime)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sync rides to Whoosh map, \(viewModel.syncEnabled ? "on" : "off")")

                rowDivider

                // Global public-sharing toggle — only interactive while sync is on.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share new rides on the Whoosh website")
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(viewModel.syncEnabled ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        if !viewModel.syncEnabled {
                            Text("Turn on sync to share rides")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.shareNewRidesPublicly },
                        set: { viewModel.setShareNewRidesPublicly($0) }
                    ))
                    .labelsHidden()
                    .disabled(!viewModel.syncEnabled)
                    .tint(Theme.Palette.lime)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Share new rides on the Whoosh website, \(viewModel.syncEnabled ? (viewModel.shareNewRidesPublicly ? "on" : "off") : "unavailable, turn on sync first")")

                rowDivider
                valueRow(title: "Privacy zone", value: "0.1 mi")
                rowDivider
                valueRow(title: "Identity", value: "Anonymous")
            }
            .cardStyle()

            Text("Uploads finished rides (stats + privacy-trimmed route) so they appear on the Whoosh website. Camera video is never uploaded. On by default; turn it off anytime. Sharing is a separate choice and only applies to rides finished while it's on.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Enable-sharing confirmation (Requirement 12.12).
        .alert(
            "Share new rides publicly?",
            isPresented: promptBinding(.confirmEnableSharing)
        ) {
            Button("Cancel", role: .cancel) { viewModel.cancelPrompt() }
            Button("Share new rides") { viewModel.confirmEnableSharing() }
        } message: {
            Text("New rides you finish will appear on the public Whoosh website: a privacy-trimmed route, distance, time, and average speed. No name or account is shown. Only rides finished while this is on are shared.")
        }
        // Disable-sharing prompt: unshare already-shared rides or keep them (12.14).
        .confirmationDialog(
            "Stop sharing new rides",
            isPresented: promptBinding(.confirmDisableSharing),
            titleVisibility: .visible
        ) {
            Button("Unshare already-shared rides", role: .destructive) {
                viewModel.confirmDisableSharingAndUnshare()
            }
            Button("Keep them shared") { viewModel.confirmDisableSharingKeepShared() }
            Button("Cancel", role: .cancel) { viewModel.cancelPrompt() }
        } message: {
            Text("New rides won't be shared. Do you also want to stop sharing the rides that are already public?")
        }
        // Disable-sync-while-shared prompt (Requirement 12.16).
        .confirmationDialog(
            "Turn off sync?",
            isPresented: promptBinding(.confirmDisableSyncWhileShared),
            titleVisibility: .visible
        ) {
            Button("Stop sharing, then turn off sync", role: .destructive) {
                viewModel.confirmDisableSyncAndUnshare()
            }
            Button("Keep rides public, turn off sync") {
                viewModel.confirmDisableSyncKeepShared()
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPrompt() }
        } message: {
            Text("Some of your rides are still shared on the Whoosh website. Turning off sync won't remove them. Stop sharing them first?")
        }
    }

    /// A binding that is `true` while the given prompt is active, so a single
    /// `activePrompt` value drives several alerts/dialogs.
    private func promptBinding(_ prompt: SettingsViewModel.Prompt) -> Binding<Bool> {
        Binding(
            get: { viewModel.activePrompt == prompt },
            set: { if !$0, viewModel.activePrompt == prompt { viewModel.cancelPrompt() } }
        )
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

    // MARK: - Apple Watch (opt-in; pushes the readiness/connect screen)

    private var appleWatchSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Apple Watch")
            NavigationLink {
                WatchReadinessView(viewModel: watchReadiness)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Watch")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Connect your watch, test the wrist buzz, and feel the ride cues.")
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
            .accessibilityLabel("Apple Watch")
            .accessibilityHint("Opens watch connection, haptics test, and ride cue previews")
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
                            Text("Add a contact and agree to the consent screen to arm alerts.")
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
                .accessibilityLabel("Crash alerts, needs a contact and consent")
                .accessibilityHint("Opens emergency contact and crash alert setup")
            }
        }
    }

    // MARK: - Safety (experimental)

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

    private func valueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
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
    let env = AppEnvironment.preview()
    return NavigationStack {
        SettingsView(viewModel: env.settingsViewModel, rearCamera: env.rearCameraSettingsViewModel, demo: env.demo, watchReadiness: env.makeWatchReadinessViewModel())
    }
}
