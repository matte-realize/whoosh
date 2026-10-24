import SwiftUI

/// The crash-alert consent and disclosure screen (spec Requirement 1 and 3,
/// task 17), pushed from the Emergency setup hub.
///
/// Presents, in plain language, exactly **what is sent** and **what is not
/// sent**, the precise-location / not-privacy-zone-trimmed notice, the
/// SMS-not-encrypted notice, the STOP explanation, and the foreground-only
/// limitation. It shows a **live preview** of the exact message a contact would
/// receive (rendered by the shared `CrashMessageBuilder`), and offers two
/// separate controls — a data-use consent and a not-a-guarantee acknowledgement
/// — that must both be on before alerts can be enabled. A revoke path clears
/// consent, disables alerts, and offers to delete the contacts.
///
/// A thin view over `ConsentViewModel`; no business logic here. Copy is phrased
/// to pass `scripts/privacy-check.sh` (it states Whoosh cannot guarantee
/// detection or delivery and never promises an emergency response).
struct ConsentView: View {
    @Bindable var viewModel: ConsentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if viewModel.needsReacceptance {
                    reacceptanceNotice
                }
                notGuaranteeCard
                whatIsSentSection
                whatIsNotSentSection
                noticesSection
                previewSection
                controlsSection
                enableButton
                if viewModel.isConsentCurrent {
                    revokeButton
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Consent & what's sent")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your contacts?", isPresented: contactDeletionBinding) {
            Button("Delete my contacts", role: .destructive) { viewModel.deleteContacts() }
            Button("Keep them", role: .cancel) { viewModel.keepContacts() }
        } message: {
            Text("Crash alerts are off. You can also remove the emergency contacts stored on this iPhone.")
        }
    }

    /// A one-way binding for the "Delete my contacts" alert: it reflects the
    /// view model's offer flag and routes a dismissal to `keepContacts()`.
    private var contactDeletionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isOfferingContactDeletion },
            set: { newValue in if !newValue { viewModel.keepContacts() } }
        )
    }

    // MARK: - Re-acceptance notice (Requirement 3.6)

    private var reacceptanceNotice: some View {
        calloutCard(
            systemImage: "arrow.triangle.2.circlepath",
            tint: Theme.Palette.amber,
            title: "Please review again",
            body: "The message wording changed, so automatic alerts are off until you accept again below."
        )
    }

    // MARK: - Not-a-guarantee (Requirement 1.1)

    private var notGuaranteeCard: some View {
        calloutCard(
            systemImage: "exclamationmark.shield",
            tint: Theme.Palette.alert,
            title: "Not a guaranteed emergency service",
            body: "Whoosh may miss a crash, may send a false alert, and cannot guarantee detection or delivery. It does not contact emergency services. Alerts work only while Whoosh is open during a ride."
        )
    }

    // MARK: - What is sent (Requirement 3.2)

    private var whatIsSentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("What is sent")
            bulletList([
                "Your name (the label you chose).",
                "The time a crash was detected, with your time-zone offset.",
                "Your precise location as map links — this is not trimmed by the ride-sync privacy zone, because a contact needs to find you.",
                "A statement that a crash was detected but an injury has not been confirmed.",
                "Your contact's phone number goes to the messaging backend and SMS provider, only when an intro, test, or alert is actually sent.",
            ])
        }
    }

    // MARK: - What is NOT sent (Requirement 3.3)

    private var whatIsNotSentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("What is never sent")
            bulletList([
                "No camera video or frames, ever.",
                "No ride history or route.",
                "No contact list.",
                "No device identifiers beyond an anonymous account.",
                "No free-form text — the backend sends a fixed message.",
            ])
        }
    }

    // MARK: - Notices (Requirement 3.4, 13.2)

    private var noticesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Please know")
            bulletList([
                "Text messages are not end-to-end encrypted. The SMS provider and carriers handle them, and delivery is not guaranteed.",
                "Each contact can reply STOP to opt out; Whoosh honors it and tells you.",
                "You are responsible for letting your contacts know they may hear from Whoosh.",
                "Alerts work only while Whoosh is open and a ride is active. They may not work if the app is closed, the phone is locked, or iOS suspends it.",
            ])
        }
    }

    // MARK: - Live message preview (Requirement 3.5)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Exactly what a contact sees")
            Text(viewModel.messagePreview)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityLabel("Example message a contact would receive")
                .accessibilityValue(viewModel.messagePreview)
            Text("Example using a sample time and location. A real alert uses your current ride details.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Two controls (Requirement 1.2 / 3.1)

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Toggle(isOn: $viewModel.dataUseConsented) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I agree to what's sent")
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Share my name, time, and precise location with my contacts when an alert is sent.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("I agree to what's sent")

            Toggle(isOn: $viewModel.acknowledgedNotGuaranteed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I understand this is not a guarantee")
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Whoosh cannot guarantee detection or delivery and does not contact emergency services.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityLabel("I understand this is not a guaranteed emergency service")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: - Actions

    private var enableButton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PrimaryButton(viewModel.isConsentCurrent ? "Update consent" : "Turn on crash alerts") {
                Task { await viewModel.enable() }
            }
            .disabled(!viewModel.canEnable)
            .opacity(viewModel.canEnable ? 1 : 0.5)
            if !viewModel.hasRiderLabel {
                Text("Add your name on the previous screen first.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("You'll be asked to allow notifications so Whoosh can show a backup prompt during a countdown.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var revokeButton: some View {
        Button(role: .destructive) {
            viewModel.revoke()
        } label: {
            Text("Revoke consent")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.alert)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Revoke consent")
        .accessibilityHint("Turns off crash alerts immediately and offers to delete your contacts")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, 6)
                    Text(item)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func calloutCard(
        systemImage: String,
        tint: Color,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(body)
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
        .accessibilityLabel("\(title). \(body)")
    }
}

#Preview("Consent — fresh") {
    NavigationStack {
        ConsentView(
            viewModel: ConsentViewModel(
                consentStore: InMemoryConsentStore(),
                settingsStore: InMemoryCrashAlertSettingsStore(
                    settings: CrashAlertSettings(riderLabel: "Alex")
                ),
                contactStore: InMemoryEmergencyContactStore(),
                scheduler: FakeCrashNotificationScheduler(),
                clock: SystemClock()
            )
        )
    }
}

#Preview("Consent — current") {
    NavigationStack {
        ConsentView(
            viewModel: ConsentViewModel(
                consentStore: InMemoryConsentStore(
                    consent: ConsentRecord(version: 1, acceptedAt: .now, acknowledgedNotGuaranteed: true)
                ),
                settingsStore: InMemoryCrashAlertSettingsStore(
                    settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
                ),
                contactStore: InMemoryEmergencyContactStore(),
                scheduler: FakeCrashNotificationScheduler(),
                clock: SystemClock()
            )
        )
    }
}
