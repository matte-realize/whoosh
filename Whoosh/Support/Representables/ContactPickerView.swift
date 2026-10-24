import SwiftUI
import ContactsUI

/// A thin SwiftUI wrapper around `CNContactPickerViewController` (spec
/// Requirement 2.1, design `Support/Representables/`).
///
/// The system contact picker runs **out-of-process** and requires **no
/// Contacts permission** for the contact the rider picks — Whoosh never calls
/// `CNContactStore` and never requests Contacts access (privacy.md
/// "Permissions": Contacts are *never requested*). The picker is configured to
/// select a single **phone number**, and only the chosen name and number cross
/// back into the app through `onPick`.
///
/// Lives under `Support/Representables/` (UIKit wrappers), the only place
/// allowed to import `ContactsUI`. The view model owns validation of the picked
/// number (`ContactEditorViewModel`); this wrapper does no normalization.
struct ContactPickerView: UIViewControllerRepresentable {
    /// Called with the picked contact's display name (may be empty) and the
    /// selected phone number's raw string. Normalization/validation happens in
    /// the view model.
    let onPick: (_ name: String, _ phoneNumber: String) -> Void
    /// Called when the rider cancels the picker without choosing anyone.
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Only show contacts that have at least one phone number, and let the
        // rider drill into a single number.
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(
            format: "phoneNumbers.@count > 0"
        )
        picker.predicateForSelectionOfContact = NSPredicate(
            format: "phoneNumbers.@count == 1"
        )
        return picker
    }

    func updateUIViewController(
        _ uiViewController: CNContactPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    /// Bridges `CNContactPickerDelegate` callbacks to the SwiftUI closures.
    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (_ name: String, _ phoneNumber: String) -> Void
        private let onCancel: () -> Void

        init(
            onPick: @escaping (_ name: String, _ phoneNumber: String) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        /// A single phone number was picked.
        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contactProperty: CNContactProperty
        ) {
            let contact = contactProperty.contact
            let name = displayName(for: contact)
            let number = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
            onPick(name, number)
        }

        /// A whole contact was picked (single-number contacts). Use its first
        /// phone number.
        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contact: CNContact
        ) {
            let name = displayName(for: contact)
            let number = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, number)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }

        private func displayName(for contact: CNContact) -> String {
            let formatted = CNContactFormatter.string(from: contact, style: .fullName)
            return formatted ?? "\(contact.givenName) \(contact.familyName)"
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
