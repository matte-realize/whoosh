import SwiftUI

/// The post-send **crash alert status screen** (spec Requirement 11.6, 12,
/// design "Other screens" → `CrashAlertStatusView`, crash-response task 21).
///
/// Shows each contact's delivery status as **icon + text** (never colour alone),
/// a banner for the queued / stale / failed cases, the rider-initiated composer
/// fallback ("Tap to text <contact> now", pre-filled by the shared builder with
/// delay wording), Copy / Share when the device can't send text
/// (`canSendText == false`, Requirement 12.8), an "I'm OK — cancel alert" action
/// for the queued state only, a clearly secondary manual "Call 911"
/// (hidden for drills), and the honest not-a-guarantee note.
///
/// A thin view over the `CrashResponseCoordinator`'s read-only state; all
/// decisions (which banner, which actions) come from the coordinator and the
/// pure reducer. Honest copy only: no claim of confirmed crash, guaranteed
/// delivery, or that Whoosh reached emergency services (it never does).
struct CrashAlertStatusView: View {
    let coordinator: CrashResponseCoordinator

    @State private var isComposerPresented = false
    @State private var isSharePresented = false
    @State private var composerPayload: CrashResponseCoordinator.ComposerFallbackPayload?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                headline
                bannerSection
                recipientsSection
                actionsSection
                disclaimer
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle(coordinator.isDrill ? "Demo alert" : "Crash alert")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isComposerPresented) {
            if let payload = composerPayload {
                MessageComposeView(
                    recipients: payload.recipients,
                    body: payload.body,
                    onFinish: { _ in
                        isComposerPresented = false
                        coordinator.composerAction()
                    }
                )
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let payload = composerPayload {
                ShareSheet(items: [payload.body])
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        let title = CrashAlertLogDisplay.title(for: coordinator.eventState, isDrill: coordinator.isDrill)
        let symbol = CrashAlertLogDisplay.systemImage(for: coordinator.eventState, isDrill: coordinator.isDrill)
        let tint = CrashAlertLogDisplay.tint(for: coordinator.eventState, isDrill: coordinator.isDrill)
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    // MARK: - Banner (queued / stale / failed)

    @ViewBuilder private var bannerSection: some View {
        if let banner = bannerCopy {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: banner.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(banner.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(banner.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(banner.title). \(banner.detail)")
        }
    }

    private struct BannerCopy {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
    }

    private var bannerCopy: BannerCopy? {
        switch coordinator.bannerKind {
        case .none, .recoveryPrompted:
            return nil
        case .queuedOffline:
            return BannerCopy(
                symbol: "wifi.slash",
                tint: Theme.Palette.amber,
                title: "Alert not sent yet",
                detail: "You're offline. Whoosh will keep trying, or you can text your contact now. It can't guarantee detection or delivery."
            )
        case .stale:
            return BannerCopy(
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.Palette.alert,
                title: "Alert not sent",
                detail: "Too much time passed, so Whoosh won't send automatically. You can text your contact now or discard."
            )
        case .failed:
            return BannerCopy(
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.Palette.alert,
                title: "Couldn't send the alert",
                detail: "The message service didn't accept it. You can text your contact now. Whoosh can't guarantee detection or delivery."
            )
        }
    }

    // MARK: - Recipients

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Contacts")
            if coordinator.recipients.isEmpty {
                Text("No reachable contacts.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(coordinator.recipients.enumerated()), id: \.element.id) { index, recipient in
                        recipientRow(recipient)
                        if index < coordinator.recipients.count - 1 {
                            rowDivider
                        }
                    }
                }
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private func recipientRow(_ recipient: CrashRecipientDisplay) -> some View {
        let statusTitle = recipient.status.map { CrashAlertLogDisplay.title(for: $0) } ?? "Preparing"
        let symbol = recipient.status.map { CrashAlertLogDisplay.systemImage(for: $0) } ?? "clock"
        let tint = recipient.status.map { CrashAlertLogDisplay.tint(for: $0) } ?? Theme.Colors.textSecondary
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("•• \(recipient.maskedNumber)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(statusTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipient.label), ending \(recipient.maskedNumber), \(statusTitle)")
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // "I'm OK — cancel alert" only while queued offline (Requirement 12.1).
            if coordinator.bannerKind == .queuedOffline {
                PrimaryButton("I'm OK — cancel alert", systemImage: "hand.raised.fill", style: .secondary) {
                    coordinator.riderCancel()
                }
                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
            }

            // Composer fallback, offered when the coordinator says so.
            if coordinator.isComposerFallbackOffered {
                fallbackButton
            }

            // Manual Call 911 — rider-tapped, hidden for drills (Requirement 17.2/17.3).
            if coordinator.isDrill {
                demoTag
            } else {
                EmergencyCallButton(style: .status)
            }
        }
    }

    @ViewBuilder private var fallbackButton: some View {
        let contactName = coordinator.recipients.first?.label ?? "your contact"
        if MessageComposeView.canSendText {
            PrimaryButton("Tap to text \(contactName) now", systemImage: "message.fill") {
                composerPayload = coordinator.composerFallback()
                if composerPayload != nil { isComposerPresented = true }
            }
        } else {
            // Device can't send text ⇒ Copy / Share (Requirement 12.8).
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    if let payload = coordinator.composerFallback() {
                        UIPasteboard.general.string = payload.body
                        coordinator.composerAction()
                    }
                } label: {
                    actionChipLabel("Copy message", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)

                Button {
                    composerPayload = coordinator.composerFallback()
                    if composerPayload != nil { isSharePresented = true }
                } label: {
                    actionChipLabel("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionChipLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Size.minTouchTarget)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .accessibilityLabel(title)
    }

    private var demoTag: some View {
        Text("Call 911 is disabled during a demo")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .accessibilityLabel("Call 911 is disabled during a demo")
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("Whoosh is not a guaranteed emergency-response service. It can't guarantee detection or delivery and does not contact emergency services.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Whoosh is not a guaranteed emergency-response service. It cannot guarantee detection or delivery and does not contact emergency services.")
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

/// A minimal `UIActivityViewController` wrapper for the Share fallback
/// (Requirement 12.8) when the device cannot send a text.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
