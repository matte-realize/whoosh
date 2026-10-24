import SwiftUI

/// Add or edit an emergency contact (spec Requirement 2.1–2.6, task 16).
///
/// The rider can pick from the system contact picker (`ContactPickerView`,
/// which requests **no** Contacts permission) or type a name and number. The
/// number is normalized and validated on Save; inline errors are shown under
/// the relevant field (Requirement 2.3/2.4). Editing a contact also offers a
/// destructive Remove, and the verification state is shown with icon + text.
///
/// A thin view over `ContactEditorViewModel`; it holds no business logic.
struct ContactEditorView: View {
    @Bindable var viewModel: ContactEditorViewModel
    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let verification = viewModel.editingVerification {
                    verificationRow(verification)
                }
                pickerButton
                nameField
                numberField
                if let formError = viewModel.formError {
                    errorText(formError)
                }
                saveButton
                if viewModel.isEditing {
                    removeButton
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle(viewModel.isEditing ? "Edit contact" : "Add contact")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            ContactPickerView(
                onPick: { name, number in
                    viewModel.applyPickedContact(name: name, phoneNumber: number)
                    showingPicker = false
                },
                onCancel: { showingPicker = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Verification state (icon + text, Requirement 2.5)

    private func verificationRow(_ verification: ContactVerification) -> some View {
        let display = ContactVerificationDisplay(verification)
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: display.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(display.tint)
            Text(display.title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status, \(display.title)")
    }

    // MARK: - Pick from Contacts

    private var pickerButton: some View {
        PrimaryButton("Choose from Contacts", systemImage: "person.crop.circle", style: .secondary) {
            showingPicker = true
        }
        .overlay(
            Capsule().stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .accessibilityHint("Opens the system contact picker. Whoosh never asks for Contacts access.")
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            fieldLabel("Name")
            TextField("First name or nickname", text: $viewModel.label)
                .textInputAutocapitalization(.words)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.md)
                .frame(minHeight: 44)
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityLabel("Contact name")
            if let labelError = viewModel.labelError {
                errorText(labelError)
            }
        }
    }

    private var numberField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            fieldLabel("Phone number")
            TextField("US or Canada mobile number", text: $viewModel.rawNumber)
                .keyboardType(.phonePad)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.md)
                .frame(minHeight: 44)
                .background(Theme.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityLabel("Contact phone number")
            if let numberError = viewModel.numberError {
                errorText(numberError)
            } else {
                Text("US and Canada mobile numbers only. Standard message rates may apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private var saveButton: some View {
        PrimaryButton(viewModel.isEditing ? "Save changes" : "Add contact") {
            viewModel.save()
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            viewModel.remove()
        } label: {
            Text("Remove contact")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.alert)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove contact")
        .accessibilityHint("Permanently removes this contact from this iPhone")
    }

    // MARK: - Helpers

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.sectionHeader)
            .tracking(0.8)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func errorText(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.alert)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.alert)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error, \(message)")
    }
}

#Preview("Add contact") {
    NavigationStack {
        ContactEditorView(
            viewModel: ContactEditorViewModel(mode: .add, store: InMemoryEmergencyContactStore())
        )
    }
}

#Preview("Edit contact") {
    let contact = EmergencyContact(
        id: UUID(),
        label: "Mom",
        e164: "+16175550123",
        verification: .reachable
    )
    return NavigationStack {
        ContactEditorView(
            viewModel: ContactEditorViewModel(
                mode: .edit(contact),
                store: InMemoryEmergencyContactStore(contacts: [contact])
            )
        )
    }
}
