import SwiftUI

/// The compact pre-ride "Connect your watch" step (owner request; watch-
/// companion Requirement 1.8). Shown before Mount & frame when a watch is
/// paired and the rider hasn't suppressed it. It states whether the watch is
/// connected or not reachable, offers a **Test buzz**, a primary **Continue**,
/// a **Skip** path, and a remembered "Don't show this again".
///
/// The view is dumb: it observes the view model and calls `onContinue` /
/// `onSkip`, which the composition root wires to proceed to Mount & frame (or
/// the normal ride). Honest copy: a wrist buzz is a cue, not a guarantee.
struct WatchConnectStepView: View {
    @State var viewModel: WatchConnectStepViewModel
    /// Proceed to the ride (Mount & frame or normal start). The step persists
    /// the suppression choice first.
    var onContinue: () -> Void
    /// Skip the watch for this ride and proceed.
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.screenBackground.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                statusCard
                Spacer()
                controls
            }
            .padding(Theme.Spacing.lg)
        }
        .onAppear { viewModel.onAppear() }
    }

    private var statusCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: viewModel.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(viewModel.isConnected ? Theme.Colors.positive : Theme.Palette.amber)

            Text(viewModel.statusTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(viewModel.statusDetail)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isWatchAppInstalled {
                Button {
                    Task { await viewModel.testBuzz() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if viewModel.isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "hand.tap.fill")
                        }
                        Text("Test buzz")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(height: 44)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
                .accessibilityHint("Sends a single test buzz to your watch.")
            }

            if let message = viewModel.lastSendMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.statusTitle). \(viewModel.statusDetail)")
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: $viewModel.dontShowAgain) {
                Text("Don't show this again")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .tint(Theme.Palette.lime)

            Button {
                viewModel.persistSuppressionChoice()
                onContinue()
            } label: {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.minTouchTarget)
                    .background(Theme.Palette.lime)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Continues to frame the camera and start the ride.")

            Button {
                viewModel.persistSuppressionChoice()
                onSkip()
            } label: {
                Text("Skip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Skips the watch step for this ride.")
        }
    }
}

#Preview("Connect — connected") {
    WatchConnectStepView(
        viewModel: WatchConnectStepViewModel(connection: FakeWatchConnection()),
        onContinue: {}, onSkip: {}
    )
}

#Preview("Connect — not reachable") {
    WatchConnectStepView(
        viewModel: WatchConnectStepViewModel(
            connection: FakeWatchConnection(isPaired: true, isWatchAppInstalled: true, isReachable: false)
        ),
        onContinue: {}, onSkip: {}
    )
}
