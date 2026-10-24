import SwiftUI

/// The demo tools panel shown inside the Settings "Demo mode" section while demo
/// mode is on (demo-mode Requirement 3.1; tasks 10–11). It wires each control to
/// an already-tested `DemoModeController` intent and keeps no logic of its own.
///
/// Tools offered: start/stop a simulated ride (with a playback-speed control),
/// Simulate approaching vehicle (one-shot and an auto-every-N toggle), Seed
/// sample data / Remove demo data (with the O-DM7 remove-first prompt on
/// re-seed), Simulate crash (drill, wired in task 12), and the state previews.
///
/// Every control is ≥ 60 pt and VoiceOver-labelled (Requirement 3.5). Copy is
/// honest and experimental — the rear cue is a cue, not a guarantee; the crash
/// action is a drill that never sends or dials.
struct DemoToolsView: View {
    @Bindable var controller: DemoModeController
    @State private var showReseedPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            simulatedRideTool
            forcedAlertTool
            crashDrillTool
            statePreviewsTool
            sampleDataTool

            if let message = controller.dataActionMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel(message)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .alert("Demo rides already exist", isPresented: $showReseedPrompt) {
            Button("Remove and re-seed") { controller.seedSampleData(removingExisting: true) }
            Button("Add anyway") { controller.seedSampleData(removingExisting: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There are \(controller.existingDemoRideCount) demo rides already. Remove them first to avoid duplicates, or add more.")
        }
    }

    // MARK: - Simulated ride

    private var simulatedRideTool: some View {
        toolCard(title: "Simulated ride") {
            if controller.activeSimulatedRide {
                toolButton("Stop simulated ride", systemImage: "stop.fill") {
                    controller.stopSimulatedRide()
                }
            } else {
                toolButton("Start simulated ride", systemImage: "play.fill") {
                    controller.startSimulatedRide()
                }
            }
            speedPicker
        }
    }

    private var speedPicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Speed")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            ForEach(([1] + DemoTuning().acceleratedSpeedFactors), id: \.self) { factor in
                Button {
                    controller.setSimulatedSpeed(factor)
                } label: {
                    Text(speedLabel(factor))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelectedSpeed(factor) ? Theme.Palette.ink : Theme.Colors.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(isSelectedSpeed(factor) ? Theme.Palette.lime : Theme.Colors.cardSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed \(speedLabel(factor))")
                .accessibilityAddTraits(isSelectedSpeed(factor) ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Forced alert

    private var forcedAlertTool: some View {
        toolCard(title: "Rear-vehicle cue") {
            toolButton("Simulate approaching vehicle", systemImage: "car.fill") {
                controller.fireRearAlertOnce()
            }
            Toggle(isOn: autoAlertBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto every \(Int(DemoTuning().autoAlertInterval)) s")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Experimental cue — cannot guarantee detection or delivery")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .tint(Theme.Palette.amber)
            .frame(minHeight: Theme.Size.minTouchTarget)
            .accessibilityLabel("Auto rear-vehicle cue every \(Int(DemoTuning().autoAlertInterval)) seconds")
        }
    }

    private var autoAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.autoAlertActive },
            set: { on in
                if on { controller.startAutoRearAlert() } else { controller.stopAutoRearAlert() }
            }
        )
    }

    // MARK: - Crash drill (wired in task 12)

    private var crashDrillTool: some View {
        toolCard(title: "Crash drill") {
            toolButton("Simulate crash (drill)", systemImage: "exclamationmark.triangle.fill") {
                controller.simulateCrashDrill()
            }
            Text("Runs the real countdown labelled DEMO — not real. Call 911 is hidden and nothing is sent.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - State previews

    private var statePreviewsTool: some View {
        toolCard(title: "State previews") {
            previewButton("Location denied", .locationDenied)
            previewButton("Signal lost", .signalLost)
            previewButton("Storage unavailable", .storageUnavailable)
            previewButton("Crash countdown", .crashCountdown)
        }
    }

    private func previewButton(_ title: String, _ preview: DemoStatePreview) -> some View {
        toolButton(title, systemImage: "eye") {
            controller.showStatePreview(preview)
        }
    }

    // MARK: - Seed / remove

    private var sampleDataTool: some View {
        toolCard(title: "Sample data") {
            toolButton("Seed sample data", systemImage: "square.stack.3d.up.fill") {
                if controller.refreshExistingDemoCount() > 0 {
                    showReseedPrompt = true
                } else {
                    controller.seedSampleData()
                }
            }
            toolButton("Remove demo data", systemImage: "trash") {
                controller.removeDemoData()
            }
        }
    }

    // MARK: - Building blocks

    private func toolCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(Theme.Typography.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func toolButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.minTouchTarget, alignment: .leading)
            .background(Theme.Colors.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func isSelectedSpeed(_ factor: Double) -> Bool {
        abs(controller.simulatedSpeedFactor - factor) < 0.0001
    }

    private func speedLabel(_ factor: Double) -> String {
        factor == factor.rounded() ? "\(Int(factor))×" : "\(factor)×"
    }
}

#Preview("DemoToolsView") {
    let env = AppEnvironment.preview()
    env.demo.isEnabled = true
    return ScrollView {
        DemoToolsView(controller: env.demo)
            .padding()
    }
    .background(Theme.Colors.screenBackground)
}
