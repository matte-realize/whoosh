import SwiftUI

/// The intro and test message flow (spec Requirement 4, task 18), pushed from
/// the Emergency setup hub.
///
/// For each contact it shows the verification state and the latest send status
/// (icon + text), with "Send intro" and "Send a test" actions. In the shipping
/// Tier 0 build no messaging backend is wired, so the screen shows an honest
/// "Messaging isn't connected yet" banner and offers a rider-initiated composer
/// fallback ("Text them yourself") prefilled from the shared
/// `CrashMessageBuilder`. The composer never sends without the rider tapping
/// Send.
///
/// A thin view over `TestAlertViewModel`; no business logic here.
struct TestAlertView: View {
    @Bindable var viewModel: TestAlertViewModel

    /// The composer fallback being presented, if any.
    @State private var composer: ComposerRequest?

    private struct ComposerRequest: Identifiable {
        let id = UUID()
        let recipients: [String]
        let body: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !viewModel.isMessagingConnected {
                    notConnectedBanner
                }
                if let message = viewModel.globalMessage {
                    globalMessageCard(message)
                }
                if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.rows) { row in
                        contactCard(row)
                    }
                }
                disclaimer
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Send a test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.reload() }
        .sheet(item: $composer) { request in
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: request.recipients,
                    body: request.body,
                    onFinish: { _ in composer = nil }
                )
                .ignoresSafeArea()
            } else {
                copyShareFallback(request)
            }
        }
    }

    // MARK: - Not connected (Tier 0)

    private var notConnectedBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Messaging isn't connected yet")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Whoosh can't send intros or tests automatically on this build. Use \"Text them yourself\" to send from your own phone.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Messaging isn't connected yet. Use Text them yourself to send from your own phone.")
    }

    private func globalMessageCard(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("No contacts yet")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Add a contact first, then send them an intro so they know Whoosh may text them.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: - Contact card

    private func contactCard(_ row: TestAlertRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    verificationLine(row.verification)
                }
                Spacer()
                sendStatusBadge(row)
            }

            if let detail = row.statusDetail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Status: \(detail)")
            }

            actions(for: row)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func verificationLine(_ verification: ContactVerification) -> some View {
        let display = ContactVerificationDisplay(verification)
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: display.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(display.tint)
            Text(display.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func sendStatusBadge(_ row: TestAlertRow) -> some View {
        switch row.sendStatus {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView()
                .accessibilityLabel("Sending")
        case let .status(status):
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: CrashAlertLogDisplay.systemImage(for: status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CrashAlertLogDisplay.tint(for: status))
                Text(CrashAlertLogDisplay.title(for: status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(CrashAlertLogDisplay.title(for: status))
        case .failed:
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.alert)
                Text("Not sent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Not sent")
        }
    }

    @ViewBuilder
    private func actions(for row: TestAlertRow) -> some View {
        if viewModel.isMessagingConnected {
            HStack(spacing: Theme.Spacing.sm) {
                PrimaryButton("Send intro", systemImage: "hand.wave", style: .secondary) {
                    Task { await viewModel.sendIntro(to: row.id) }
                }
                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
                PrimaryButton("Send a test", systemImage: "paperplane", style: .secondary) {
                    Task { await viewModel.sendTest(to: row.id) }
                }
                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
            }
            textThemYourself(row, title: "Text them yourself")
        } else {
            // Tier 0: only the rider-initiated composer fallback.
            HStack(spacing: Theme.Spacing.sm) {
                composerButton(row, kind: .intro, title: "Text intro")
                composerButton(row, kind: .test, title: "Text a test")
            }
        }
    }

    private func textThemYourself(_ row: TestAlertRow, title: String) -> some View {
        Button {
            composer = ComposerRequest(
                recipients: viewModel.composerRecipients(for: row.id),
                body: viewModel.composerBody(for: row.id, kind: .intro)
            )
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Messages app prefilled. Nothing sends until you tap Send.")
    }

    private func composerButton(_ row: TestAlertRow, kind: CrashMessageKind, title: String) -> some View {
        PrimaryButton(title, systemImage: "square.and.pencil", style: .secondary) {
            composer = ComposerRequest(
                recipients: viewModel.composerRecipients(for: row.id),
                body: viewModel.composerBody(for: row.id, kind: kind)
            )
        }
        .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
        .accessibilityHint("Opens the Messages app prefilled. Nothing sends until you tap Send.")
    }

    // MARK: - Copy / Share fallback (canSendText == false, Requirement 12.8)

    private func copyShareFallback(_ request: ComposerRequest) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("This device can't send texts")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(request.body)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Copy message", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = request.body
            }
            ShareLink(item: request.body) {
                Text("Share")
                    .font(.system(size: 15, weight: .semibold))
            }
            PrimaryButton("Done", style: .secondary) { composer = nil }
        }
        .padding(Theme.Spacing.xl)
        .presentationDetents([.medium])
    }

    // MARK: - Disclaimer (honest copy, Requirement 1)

    private var disclaimer: some View {
        Text("A test or intro uses the same path as a real alert, so a successful one is good evidence it works. Whoosh still cannot guarantee detection or delivery.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Test flow — connected") {
    let contacts = [
        EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable),
        EmergencyContact(id: UUID(), label: "Sam", e164: "+16175550124", verification: .unverified),
    ]
    return NavigationStack {
        TestAlertView(
            viewModel: TestAlertViewModel(
                notifier: FakeCrashNotifier(),
                contactStore: InMemoryEmergencyContactStore(contacts: contacts),
                connectivity: FakeConnectivityMonitor(isOnline: true),
                settingsStore: InMemoryCrashAlertSettingsStore(
                    settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
                ),
                clock: SystemClock(),
                isMessagingConnected: true
            )
        )
    }
}

#Preview("Test flow — Tier 0 (Noop)") {
    let contacts = [
        EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .unverified),
    ]
    return NavigationStack {
        TestAlertView(
            viewModel: TestAlertViewModel(
                notifier: NoopCrashNotifier(),
                contactStore: InMemoryEmergencyContactStore(contacts: contacts),
                connectivity: FakeConnectivityMonitor(isOnline: true),
                settingsStore: InMemoryCrashAlertSettingsStore(
                    settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
                ),
                clock: SystemClock(),
                isMessagingConnected: false
            )
        )
    }
}
