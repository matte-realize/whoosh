import Foundation
import Testing
@testable import Whoosh

/// Tests for `ContactEditorViewModel` (crash-response task 16, Requirements
/// 2.1–2.6). Validation error mapping, max-contacts enforcement, add/edit/remove,
/// and the verification-reset-on-number-change rule are all verified with an
/// in-memory store and no UI.
@MainActor
struct ContactEditorViewModelTests {
    private func makeStore(
        _ contacts: [EmergencyContact] = [],
        maxContacts: Int = 3
    ) -> InMemoryEmergencyContactStore {
        InMemoryEmergencyContactStore(contacts: contacts, maxContacts: maxContacts)
    }

    private func contact(
        _ id: UUID = UUID(),
        label: String = "Mom",
        e164: String = "+16175550123",
        verification: ContactVerification = .unverified
    ) -> EmergencyContact {
        EmergencyContact(id: id, label: label, e164: e164, verification: verification)
    }

    // MARK: - Add + normalization

    @Test func addNormalizesAndSavesValidNumber() throws {
        let store = makeStore()
        var finished = false
        let vm = ContactEditorViewModel(mode: .add, store: store, onFinish: { finished = true })
        vm.label = "Mom"
        vm.rawNumber = "(617) 555-0123"
        vm.save()

        #expect(finished)
        #expect(vm.numberError == nil)
        let saved = try store.contacts()
        #expect(saved.count == 1)
        #expect(saved.first?.e164 == "+16175550123")
        #expect(saved.first?.label == "Mom")
        #expect(saved.first?.verification == .unverified)
    }

    @Test func addTrimsLabelWhitespace() throws {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "  Dad  "
        vm.rawNumber = "617-555-0123"
        vm.save()
        #expect(try store.contacts().first?.label == "Dad")
    }

    // MARK: - Validation error mapping (Requirement 2.3/2.4)

    @Test func emptyLabelShowsLabelError() throws {
        let store = makeStore()
        var finished = false
        let vm = ContactEditorViewModel(mode: .add, store: store, onFinish: { finished = true })
        vm.label = "   "
        vm.rawNumber = "617-555-0123"
        vm.save()
        #expect(vm.labelError != nil)
        #expect(finished == false)
        #expect(try store.contacts().isEmpty)
    }

    @Test func emptyNumberShowsEmptyError() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.rawNumber = ""
        vm.save()
        #expect(vm.numberError == ContactEditorViewModel.message(for: .empty))
    }

    @Test func tooShortNumberShowsWrongLengthError() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.rawNumber = "617-555"
        vm.save()
        #expect(vm.numberError == ContactEditorViewModel.message(for: .wrongLength))
    }

    @Test func nonUSNumberShowsNotNANPError() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.rawNumber = "+447911123456"
        vm.save()
        #expect(vm.numberError == ContactEditorViewModel.message(for: .notNANP))
    }

    @Test func invalidAreaCodeShowsAreaCodeError() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.rawNumber = "111-555-0123"
        vm.save()
        #expect(vm.numberError == ContactEditorViewModel.message(for: .invalidAreaCode))
    }

    @Test func everyE164ErrorMapsToDistinctNonEmptyMessage() {
        var messages: Set<String> = []
        for error in [E164Error.empty, .wrongLength, .notNANP, .invalidAreaCode, .invalidExchangeCode] {
            let message = ContactEditorViewModel.message(for: error)
            #expect(!message.isEmpty)
            messages.insert(message)
        }
        #expect(messages.count == 5)
    }

    @Test func invalidInputIsNotSaved() throws {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.rawNumber = "nonsense"
        vm.save()
        #expect(vm.numberError != nil)
        #expect(try store.contacts().isEmpty)
    }

    // MARK: - Max contacts (Requirement 2.2)

    @Test func addBeyondMaxShowsLimitMessage() throws {
        let store = makeStore(
            [contact(label: "A", e164: "+16175550101"),
             contact(label: "B", e164: "+16175550102"),
             contact(label: "C", e164: "+16175550103")],
            maxContacts: 3
        )
        var finished = false
        let vm = ContactEditorViewModel(mode: .add, store: store, maxContacts: 3, onFinish: { finished = true })
        vm.label = "D"
        vm.rawNumber = "617-555-0104"
        vm.save()
        #expect(vm.formError != nil)
        #expect(vm.formError?.contains("3") == true)
        #expect(finished == false)
        #expect(try store.contacts().count == 3)
    }

    // MARK: - Edit + verification reset (Requirement 2.6)

    @Test func editingNumberResetsVerification() throws {
        let existing = contact(e164: "+16175550123", verification: .reachable)
        let store = makeStore([existing])
        let vm = ContactEditorViewModel(mode: .edit(existing), store: store)
        #expect(vm.isEditing)
        #expect(vm.editingVerification == .reachable)
        vm.rawNumber = "617-555-0999"
        vm.save()
        let stored = try store.contacts().first
        #expect(stored?.e164 == "+16175550999")
        #expect(stored?.verification == .unverified)
    }

    @Test func editingLabelOnlyPreservesVerification() throws {
        let existing = contact(label: "Mom", e164: "+16175550123", verification: .reachable)
        let store = makeStore([existing])
        let vm = ContactEditorViewModel(mode: .edit(existing), store: store)
        vm.label = "Mum"
        // Keep the same number.
        vm.save()
        let stored = try store.contacts().first
        #expect(stored?.label == "Mum")
        #expect(stored?.verification == .reachable)
    }

    // MARK: - Remove (Requirement 2.6)

    @Test func removeDeletesContact() throws {
        let existing = contact()
        let store = makeStore([existing])
        var finished = false
        let vm = ContactEditorViewModel(mode: .edit(existing), store: store, onFinish: { finished = true })
        vm.remove()
        #expect(finished)
        #expect(try store.contacts().isEmpty)
    }

    @Test func removeInAddModeIsNoOp() throws {
        let store = makeStore([contact()])
        var finished = false
        let vm = ContactEditorViewModel(mode: .add, store: store, onFinish: { finished = true })
        vm.remove()
        #expect(finished == false)
        #expect(try store.contacts().count == 1)
    }

    // MARK: - Picker fill

    @Test func applyPickedContactFillsFields() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.applyPickedContact(name: "Alex Rivera", phoneNumber: "(617) 555-0123")
        #expect(vm.label == "Alex Rivera")
        #expect(vm.rawNumber == "(617) 555-0123")
    }

    @Test func applyPickedContactKeepsExistingLabelWhenNameEmpty() {
        let store = makeStore()
        let vm = ContactEditorViewModel(mode: .add, store: store)
        vm.label = "Mom"
        vm.applyPickedContact(name: "   ", phoneNumber: "617-555-0123")
        #expect(vm.label == "Mom")
        #expect(vm.rawNumber == "617-555-0123")
    }
}
