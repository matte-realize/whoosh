import SwiftUI

/// The Emergency setup hub, pushed from Settings → "Crash alerts" (spec
/// Requirement 2, design "Other screens").
///
/// Shows an honest on/off status with the not-a-guarantee note, the rider
/// label, the contact list (each row with its verification state as icon +
/// text), and entry points. Consent (task 17) and the test flow (task 18) are
/// not built yet: their rows render as "Coming soon" and are wired later via
/// the view model's optional nav hooks. The crash alert log row (task 22) and
/// the add/edit-contact entry points are live.
///
/// A thin view over `EmergencySetupViewModel`; no business logic here.
struct EmergencySetupView: View {
    @Bindable var viewModel: EmergencySetupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                statusSection
                riderLabelSection
                contactsSection
                verifyAndConsentSection
                logRow
                developerToolsSection
                disclaimer
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Crash alerts")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.reload() }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: viewModel.isReadyToArm ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(viewModel.isReadyToArm ? Theme.Colors.positive : Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isReadyToArm ? "Crash alerts on" : "Crash alerts off")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(statusSubtitle)
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
        .accessibilityLabel("\(viewModel.isReadyToArm ? "Crash alerts on" : "Crash alerts off"). \(statusSubtitle)")
    }

    private var statusSubtitle: String {
        if viewModel.isReadyToArm {
            return "Set up on this iPhone. Whoosh can't guarantee detection or delivery."
        }
        if !viewModel.hasRiderLabel {
            return "Add your name below to continue."
        }
        if !viewModel.hasReachableContact {
            return "Add and verify a contact to finish setting up."
        }
        return "Finish setup to turn on crash alerts."
    }

    // MARK: - Rider label

    private var riderLabelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Your name")
            TextField("First name or nickname", text: $viewModel.riderLabel)
                .textInputAutocapitalization(.words)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.md)
                .frame(minHeight: 44)
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityLabel("Your name used in messages")
            Text("Shown to your contacts so they know who the alert is about.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Contacts

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                sectionHeader("Contacts")
                Spacer()
                Text("\(viewModel.contacts.count) of \(viewModel.contacts.count + viewModel.remainingContactSlots)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if viewModel.contacts.isEmpty {
                emptyContactsRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.contacts.enumerated()), id: \.element.id) { index, contact in
                        Button {
                            viewModel.editContact(contact)
                        } label: {
                            contactRow(contact)
                        }
                        .buttonStyle(.plain)
                        if index < viewModel.contacts.count - 1 {
                            rowDivider
                        }
                    }
                }
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }

            if viewModel.canAddContact {
                PrimaryButton("Add a contact", systemImage: "plus", style: .secondary) {
                    viewModel.addContact()
                }
                .overlay(Capsule().stroke(Theme.Colors.separator, lineWidth: 1))
            } else {
                Text("You can add up to \(viewModel.contacts.count) contacts.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var emptyContactsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("No contacts yet")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Add 1 to 3 trusted people who would be texted if a crash is detected.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No contacts yet. Add 1 to 3 trusted people who would be texted if a crash is detected.")
    }

    private func contactRow(_ contact: EmergencyContact) -> some View {
        let display = ContactVerificationDisplay(contact.verification)
        return HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.label)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: display.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(display.tint)
                    Text(display.title)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contact.label), \(display.title)")
        .accessibilityHint("Edit this contact")
    }

    // MARK: - Verify / consent (wired later)

    private var verifyAndConsentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Verify & consent")
            VStack(spacing: 0) {
                hubRow(
                    title: "Consent & what's sent",
                    systemImage: "doc.text",
                    isWired: viewModel.onOpenConsent != nil,
                    action: { viewModel.onOpenConsent?() }
                )
                rowDivider
                hubRow(
                    title: "Send a test message",
                    systemImage: "paperplane",
                    isWired: viewModel.onOpenTest != nil,
                    action: { viewModel.onOpenTest?() }
                )
            }
            .background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private var logRow: some View {
        VStack(spacing: 0) {
            hubRow(
                title: "Crash alert log",
                systemImage: "list.bullet.rectangle",
                isWired: true,
                action: { viewModel.onOpenLog() }
            )
        }
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func hubRow(
        title: String,
        systemImage: String,
        isWired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { if isWired { action() } }) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(isWired ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(isWired ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                Spacer()
                if isWired {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("Coming soon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isWired)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isWired ? title : "\(title), coming soon")
    }

    // MARK: - Developer / demo tools (task 23)

    private var developerToolsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Developer / demo tools")
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer / demo tools")
                            .font(Theme.Typography.rowTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Reveals a Simulate crash control for demos and testing.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.developerToolsEnabled)
                        .labelsHidden()
                        .tint(Theme.Palette.lime)
                }
                .padding(Theme.Spacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Developer and demo tools, \(viewModel.developerToolsEnabled ? "on" : "off")")

                if viewModel.developerToolsEnabled {
                    rowDivider
                    Button {
                        viewModel.simulateCrash()
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "theatermasks")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Palette.alert)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Simulate crash")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Runs the real countdown as a demo (no real crash).")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(Theme.Spacing.md)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Simulate crash")
                    .accessibilityHint("Runs the real crash countdown as a demo. No real crash occurs.")
                }
            }
            .background(Theme.Colors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    // MARK: - Disclaimer (honest copy, Requirement 1.1/1.3)

    private var disclaimer: some View {
        Text("Whoosh is not a guaranteed emergency-response service. It may miss a crash, send a false alert, and cannot guarantee detection or delivery. It does not contact emergency services. Alerts work only while Whoosh is open during a ride.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Important: Whoosh is not a guaranteed emergency-response service and cannot guarantee detection or delivery. It does not contact emergency services.")
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

#Preview("Setup — empty") {
    NavigationStack {
        EmergencySetupView(
            viewModel: EmergencySetupViewModel(
                contactStore: InMemoryEmergencyContactStore(),
                settingsStore: InMemoryCrashAlertSettingsStore()
            )
        )
    }
}

#Preview("Setup — with contacts") {
    let contacts = [
        EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123", verification: .reachable),
        EmergencyContact(id: UUID(), label: "Sam", e164: "+16175550124", verification: .introSent),
    ]
    return NavigationStack {
        EmergencySetupView(
            viewModel: EmergencySetupViewModel(
                contactStore: InMemoryEmergencyContactStore(contacts: contacts),
                settingsStore: InMemoryCrashAlertSettingsStore(
                    settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
                )
            )
        )
    }
}
