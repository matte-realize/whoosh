import SwiftUI

/// The Settings "Apple Watch" screen (watch-companion task 22; Requirement
/// 3.1–3.10, 1.8, 13.3). Pushed from Settings on the Home `NavigationStack`.
///
/// Shows, in order:
/// - a **checklist** (icon + text) of paired / installed / connected / wrist
///   buzz / audio backup, driven by `WatchReadinessViewModel`;
/// - **Buzz my watch** and "I felt it / I didn't" so the rider confirms haptics
///   really reach the wrist (a cue, not a guarantee);
/// - **Feel the patterns** — the rear-vehicle, camera-stopped, and crash-
///   countdown cues, so the rider learns them before a ride (never starts a
///   countdown);
/// - short **install / pair steps** when the watch app isn't installed.
///
/// The view is dumb: it observes the view model and sends intents. Haptics
/// honesty: copy frames the wrist cue as experimental and never promises
/// delivery.
struct WatchReadinessView: View {
    @State var viewModel: WatchReadinessViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                checklistSection
                if viewModel.canTestHaptics {
                    buzzSection
                    patternsSection
                } else {
                    installSteps
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.onAppear() }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Readiness")
            VStack(spacing: 0) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { rowDivider }
                    checklistRow(row)
                }
            }
            .cardStyle()
            Text("Your watch shows the ride and buzzes for cues. It's a cue, not a guarantee — a muted, sleeping, or low-battery watch may not buzz, and Whoosh can't guarantee detection or delivery.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checklistRow(_ row: WatchReadinessViewModel.DisplayRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: row.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint(for: row.tone))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.detail)")
    }

    private func tint(for tone: WatchReadinessViewModel.DisplayRow.Tone) -> Color {
        switch tone {
        case .pass: return Theme.Colors.positive
        case .warn: return Theme.Palette.amber
        case .info: return Theme.Colors.textSecondary
        }
    }

    // MARK: - Buzz my watch

    private var buzzSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Test the buzz")
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Button {
                    Task { await viewModel.buzzMyWatch() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if viewModel.isSending {
                            ProgressView().tint(Theme.Palette.ink)
                        } else {
                            Image(systemName: "hand.tap.fill")
                        }
                        Text("Buzz my watch")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.minTouchTarget)
                    .background(Theme.Palette.lime)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
                .accessibilityHint("Sends a single test buzz to your watch.")

                if let message = viewModel.lastSendMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Felt-it confirmation.
                HStack(spacing: Theme.Spacing.md) {
                    feltButton(title: "I felt it", felt: true)
                    feltButton(title: "I didn't", felt: false)
                }

                if viewModel.showsTroubleshooting {
                    Text("Still nothing? Open Whoosh on your watch, make sure it isn't in Silent or Theater mode, turn the wrist up, and keep it charged. Whoosh falls back to an audio cue on your phone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
        }
    }

    private func feltButton(title: String, felt: Bool) -> some View {
        Button {
            viewModel.reportFelt(felt)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(felt ? "I felt the buzz" : "I didn't feel the buzz")
    }

    // MARK: - Feel the patterns

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Feel the patterns")
            VStack(spacing: 0) {
                ForEach(Array(viewModel.patterns.enumerated()), id: \.element.id) { index, pattern in
                    if index > 0 { rowDivider }
                    Button {
                        Task { await viewModel.previewPattern(pattern) }
                    } label: {
                        HStack {
                            Text(pattern.label)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "play.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(minHeight: Theme.Size.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending)
                    .accessibilityLabel("Preview the \(pattern.label) buzz")
                }
            }
            .cardStyle()
            Text("Previewing a pattern only buzzes your watch. It never starts a ride, a countdown, or an alert.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Install / pair steps

    private var installSteps: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader(viewModel.isPaired ? "Install the watch app" : "Pair your watch")
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !viewModel.isPaired {
                    stepRow(1, "Pair an Apple Watch with this iPhone in Apple's Watch app.")
                    stepRow(2, "Come back here — the checklist updates automatically.")
                } else {
                    stepRow(1, "In Xcode, choose the WhooshWatch scheme and your Apple Watch as the destination.")
                    stepRow(2, "Build and run so the watch app installs, then open Whoosh on your watch.")
                    stepRow(3, "Return here — the checklist updates automatically.")
                }
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
            Text("The watch companion is opt-in and experimental. Every ride works without it — Whoosh falls back to audio cues on your phone.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 24, height: 24)
                .background(Theme.Palette.lime)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
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

private extension View {
    func cardStyle() -> some View {
        background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview("Apple Watch — connected") {
    NavigationStack {
        WatchReadinessView(viewModel: WatchReadinessViewModel(connection: FakeWatchConnection()))
    }
}

#Preview("Apple Watch — not installed") {
    NavigationStack {
        WatchReadinessView(
            viewModel: WatchReadinessViewModel(
                connection: FakeWatchConnection(isPaired: true, isWatchAppInstalled: false, isReachable: false)
            )
        )
    }
}
