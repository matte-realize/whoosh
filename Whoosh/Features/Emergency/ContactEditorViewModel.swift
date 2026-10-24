import Foundation
import Observation

/// View model for `ContactEditorView` (spec Requirement 2.1–2.6, task 16).
///
/// Backs adding a new emergency contact or editing an existing one. The number
/// may be typed manually or arrive from the system contact picker
/// (`ContactPickerView`, which requests no Contacts permission). The view model
/// normalizes the number to E.164 via the pure `E164Normalizer`, maps each
/// typed error to an inline, actionable message (Requirement 2.3/2.4), enforces
/// the max-contacts limit (Requirement 2.2), and persists through the injected
/// `EmergencyContactStore`.
///
/// Editing the number of an existing contact resets its verification to
/// `unverified` — that rule lives in the store (`update`), so this view model
/// just submits the edited contact and the store applies the reset
/// (Requirement 2.6).
///
/// UI-framework-free (no SwiftUI import), per the layering table; the label and
/// number are plain `String` bindings the view owns.
@Observable
@MainActor
final class ContactEditorViewModel {
    /// Whether this editor is adding a new contact or editing an existing one.
    enum Mode: Equatable {
        case add
        case edit(EmergencyContact)
    }

    @ObservationIgnored private let store: EmergencyContactStore
    @ObservationIgnored private let mode: Mode
    @ObservationIgnored private let maxContacts: Int
    /// Called after a successful save/remove so the hub can refresh and dismiss.
    @ObservationIgnored private let onFinish: () -> Void

    /// The editable display label (first name or nickname).
    var label: String
    /// The editable raw phone number (manual entry or picker-provided).
    var rawNumber: String
    /// An inline, actionable error for the number field, or `nil` when valid.
    var numberError: String?
    /// An inline error for the label field, or `nil` when valid.
    var labelError: String?
    /// A general, non-field error (for example the contact-limit message).
    var formError: String?

    init(
        mode: Mode,
        store: EmergencyContactStore,
        maxContacts: Int = CrashResponseTuning().maxContacts,
        onFinish: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.store = store
        self.maxContacts = maxContacts
        self.onFinish = onFinish
        switch mode {
        case .add:
            self.label = ""
            self.rawNumber = ""
        case let .edit(contact):
            self.label = contact.label
            self.rawNumber = contact.e164
        }
    }

    /// `true` when editing an existing contact (controls the Remove button and
    /// the navigation title in the view).
    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The verification state of the contact being edited, for display; `nil`
    /// when adding.
    var editingVerification: ContactVerification? {
        if case let .edit(contact) = mode { return contact.verification }
        return nil
    }

    /// Fill the fields from a picked system contact. Validation happens on save.
    func applyPickedContact(name: String, phoneNumber: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            label = trimmedName
        }
        rawNumber = phoneNumber
    }

    /// Validate and save the contact. On success, calls `onFinish`. On failure,
    /// sets the relevant inline error and does not persist (Requirement 2.3).
    func save() {
        numberError = nil
        labelError = nil
        formError = nil

        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            labelError = "Enter a name for this contact."
            return
        }

        let normalized: String
        do {
            normalized = try E164Normalizer.normalize(rawNumber)
        } catch let error as E164Error {
            numberError = Self.message(for: error)
            return
        } catch {
            numberError = "Enter a valid US or Canada phone number."
            return
        }

        do {
            switch mode {
            case .add:
                let contact = EmergencyContact(
                    id: UUID(),
                    label: trimmedLabel,
                    e164: normalized
                )
                try store.add(contact)
            case let .edit(existing):
                // Submit the edited contact; the store resets verification when
                // the number changed (Requirement 2.6).
                let edited = EmergencyContact(
                    id: existing.id,
                    label: trimmedLabel,
                    e164: normalized,
                    verification: existing.verification,
                    lastStatusAt: existing.lastStatusAt
                )
                try store.update(edited)
            }
        } catch let ContactStoreError.contactLimitReached(max) {
            formError = "You can add up to \(max) emergency contacts."
            return
        } catch {
            formError = "Couldn't save this contact. Please try again."
            return
        }

        onFinish()
    }

    /// Remove the contact being edited (real deletion, Requirement 2.6). A no-op
    /// when adding.
    func remove() {
        guard case let .edit(contact) = mode else { return }
        formError = nil
        do {
            try store.remove(id: contact.id)
        } catch {
            formError = "Couldn't remove this contact. Please try again."
            return
        }
        onFinish()
    }

    /// Map an `E164Error` to an inline, actionable message (Requirement 2.3/2.4).
    static func message(for error: E164Error) -> String {
        switch error {
        case .empty:
            return "Enter a phone number."
        case .wrongLength:
            return "Enter a 10-digit US or Canada phone number."
        case .notNANP:
            return "Only US and Canada numbers are supported right now."
        case .invalidAreaCode:
            return "That area code isn't valid. Check the number."
        case .invalidExchangeCode:
            return "That number isn't valid. Check the digits after the area code."
        }
    }
}
