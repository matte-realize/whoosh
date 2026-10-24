import SwiftUI

/// The "Rear camera" Settings section (rear-camera spec Requirement 18.1, 2.1–2.7;
/// task 20). Realises the rows the design lists: a "Record rear camera" toggle
/// (off by default; enabling shows the first-enable explanation, then the
/// permission prompt), a camera choice (Back / Front), Quality (Standard /
/// Efficient), Ride mode, Buffer length, clip storage used, and — when access is
/// denied/restricted — a calm explanation with an "Open Settings" button.
///
/// The view is dumb: it observes `RearCameraSettingsViewModel` and sends intents.
/// It imports no AVFoundation (the `CameraPermission` seam owns that).
struct RearCameraSettingsSection: View {
    @Bindable var viewModel: RearCameraSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Rear camera")
            VStack(spacing: 0) {
                recordToggleRow
                if viewModel.showsDeniedState {
                    rowDivider
                    deniedRow
                }
                if viewModel.recordingEnabled {
                    rowDivider
                    cameraChoiceRow
                    rowDivider
                    qualityRow
                    rowDivider
                    rideModeRow
                    rowDivider
                    bufferLengthRow
                    rowDivider
                    storageUsedRow
                }
            }
            .cardStyle()

            Text("Records the road behind you to this iPhone while you ride. Video is saved only on your phone and is never uploaded. Other people — faces and license plates — can appear in the footage; clips are easy to delete and auto-expire. Recording is for your own records and may fail — heat, low storage, or a locked phone can stop it. Laws on recording in public vary by place.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { viewModel.refreshStorageUsed() }
        // First-enable explanation sheet (Requirement 2.1): shown before the
        // system prompt, never claiming assured capture.
        .sheet(isPresented: $viewModel.isShowingExplanation) {
            RearCameraExplanationSheet(
                onContinue: { Task { await viewModel.acknowledgeExplanation() } },
                onCancel: { viewModel.dismissExplanation() }
            )
        }
    }

    // MARK: - Rows

    private var recordToggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Record rear camera")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("On by default; video stays on this iPhone")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.recordingEnabled },
                set: { viewModel.setRecordingEnabled($0) }
            ))
            .labelsHidden()
            .tint(Theme.Palette.lime)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Record rear camera, \(viewModel.recordingEnabled ? "on" : "off")")
    }

    private var deniedRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "video.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("Camera access is off")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Text("Whoosh can't record without camera access. You can still record rides and see your history. Turn on camera access in Settings to record the road behind you.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { viewModel.openSystemSettings() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.lime)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera access is off. Rides and history still work.")
        .accessibilityHint("Open Settings to turn on camera access")
    }

    private var cameraChoiceRow: some View {
        HStack {
            Text("Camera")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Picker("Camera", selection: Binding(
                get: { viewModel.settings.cameraPosition },
                set: { viewModel.setCameraPosition($0) }
            )) {
                ForEach(CameraDevicePosition.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera, \(viewModel.settings.cameraPosition.displayName)")
    }

    private var qualityRow: some View {
        HStack {
            Text("Quality")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Picker("Quality", selection: Binding(
                get: { viewModel.settings.quality },
                set: { viewModel.setQuality($0) }
            )) {
                ForEach(CaptureQuality.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quality, \(viewModel.settings.quality.displayName)")
    }

    private var rideModeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ride mode")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Dims the screen so the phone looks off while recording. The red recording dot stays visible.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.settings.rideModeEnabled },
                set: { viewModel.setRideModeEnabled($0) }
            ))
            .labelsHidden()
            .tint(Theme.Palette.lime)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ride mode, \(viewModel.settings.rideModeEnabled ? "on" : "off")")
    }

    private var bufferLengthRow: some View {
        let minutes = Int((viewModel.settings.bufferLengthSeconds / 60).rounded())
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Buffer length")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(minutes) min")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.settings.bufferLengthSeconds },
                    set: { viewModel.setBufferLengthSeconds($0) }
                ),
                in: viewModel.bufferLengthRange,
                step: 60
            )
            .tint(Theme.Palette.lime)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Buffer length, \(minutes) minutes")
    }

    private var storageUsedRow: some View {
        HStack {
            Text("Clip storage used")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(storageUsedText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clip storage used, \(storageUsedText)")
    }

    private var storageUsedText: String {
        let bytes = viewModel.clipBytesUsed ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.md)
    }
}

// MARK: - Explanation sheet

/// The first-enable explanation shown before the camera prompt (Requirement
/// 2.1, 16.2, 16.6): what is recorded, that it stays on the device, that other
/// people may appear, and that local laws vary. Honest copy only — it never
/// calls footage evidence or claims assured capture.
private struct RearCameraExplanationSheet: View {
    let onContinue: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Record the road behind you")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    explanationRow(
                        icon: "iphone.gen3",
                        title: "Saved on your phone",
                        detail: "Clips are stored only on this iPhone and are never uploaded or attached to any message. You can delete them anytime, and they auto-expire."
                    )
                    explanationRow(
                        icon: "person.2",
                        title: "Other people may appear",
                        detail: "Faces and license plates of other road users can be in the footage. Retention is short and deletion is easy."
                    )
                    explanationRow(
                        icon: "exclamationmark.triangle",
                        title: "For your own records",
                        detail: "Recording is for your own records. It may fail — heat, low storage, or a locked phone can stop it — so some moments may not be recorded."
                    )
                    explanationRow(
                        icon: "building.columns",
                        title: "Local laws vary",
                        detail: "Rules on recording in public differ by place. This is information only, not legal advice."
                    )
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.screenBackground)
            .navigationTitle("Rear camera")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: { dismiss(); onContinue() }) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.lime)

                    Button("Not now") { dismiss(); onCancel() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minHeight: 44)
                }
                .padding(Theme.Spacing.lg)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func explanationRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.Palette.lime)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Card background modifier

private extension View {
    func cardStyle() -> some View {
        background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview("Rear camera settings") {
    let env = AppEnvironment.preview()
    return ScrollView {
        RearCameraSettingsSection(viewModel: env.rearCameraSettingsViewModel)
            .padding()
    }
    .background(Theme.Colors.screenBackground)
}
