import Foundation
import Testing
@testable import Whoosh

/// Tests for `EmergencySetupViewModel` (crash-response task 16, Requirement 2).
/// Rider-label persistence/sanitization, the contact list, the add-limit, and
/// the derived readiness summary are verified with in-memory stores and no UI.
@MainActor
struct EmergencySetupViewModelTests {
    private func contact(
        _ id: UUID = UUID(),
        label: String = "Mom",
        e164: String = "+16175550123",
        verification: ContactVerification = .unverified
    ) -> EmergencyContact {
        EmergencyContact(id: id, label: label, e164: e164, verification: verification)
    }

    private func makeViewModel(
        contacts: [EmergencyContact] = [],
        settings: CrashAlertSettings = CrashAlertSettings(),
        maxContacts: Int = 3
    ) -> (EmergencySetupViewModel, InMemoryEmergencyContactStore, InMemoryCrashAlertSettingsStore) {
        let contactStore = InMemoryEmergencyContactStore(contacts: contacts, maxContacts: maxContacts)
        let settingsStore = InMemoryCrashAlertSettingsStore(settings: settings)
        let vm = EmergencySetupViewModel(
            contactStore: contactStore,
            settingsStore: settingsStore,
            maxContacts: maxContacts
        )
        return (vm, contactStore, settingsStore)
    }

    // MARK: - Initial load

    @Test func loadsContactsAndLabelFromStores() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(label: "Mom"), contact(label: "Dad", e164: "+16175550124")],
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        #expect(vm.contacts.map(\.label) == ["Mom", "Dad"])
        #expect(vm.riderLabel == "Alex")
        #expect(vm.isEnabled)
    }

    @Test func defaultsAreOnButEmpty() {
        // Crash alerts default on (hackathon build); they still arm only after
        // a contact, a rider label and consent exist.
        let (vm, _, _) = makeViewModel()
        #expect(vm.contacts.isEmpty)
        #expect(vm.riderLabel.isEmpty)
        #expect(vm.isEnabled == true)
        #expect(vm.hasRiderLabel == false)
    }

    // MARK: - Rider label (Requirement 2.9)

    @Test func settingRiderLabelPersistsSanitized() {
        let (vm, _, settingsStore) = makeViewModel()
        vm.riderLabel = "Alex"
        #expect(settingsStore.current().riderLabel == "Alex")
        #expect(vm.hasRiderLabel)
    }

    @Test func riderLabelIsSanitizedToGSM7Charset() {
        let (vm, _, settingsStore) = makeViewModel()
        // Smart quote + emoji should be stripped/mapped by the GSM-7 sanitizer.
        vm.riderLabel = "Álex 😀"
        let stored = settingsStore.current().riderLabel
        #expect(stored != nil)
        #expect(GSM7Sanitizer.isGSM7(stored ?? ""))
    }

    @Test func clearingRiderLabelStoresNil() {
        let (vm, _, settingsStore) = makeViewModel(settings: CrashAlertSettings(riderLabel: "Alex"))
        vm.riderLabel = "   "
        #expect(settingsStore.current().riderLabel == nil)
        #expect(vm.hasRiderLabel == false)
    }

    // MARK: - Add limit (Requirement 2.2)

    @Test func canAddUntilMaxReached() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(label: "A", e164: "+16175550101"),
                       contact(label: "B", e164: "+16175550102")],
            maxContacts: 3
        )
        #expect(vm.canAddContact)
        #expect(vm.remainingContactSlots == 1)
    }

    @Test func cannotAddAtMax() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(label: "A", e164: "+16175550101"),
                       contact(label: "B", e164: "+16175550102"),
                       contact(label: "C", e164: "+16175550103")],
            maxContacts: 3
        )
        #expect(vm.canAddContact == false)
        #expect(vm.remainingContactSlots == 0)
    }

    // MARK: - Reachable / readiness

    @Test func hasReachableContactReflectsVerification() {
        let (noneReachable, _, _) = makeViewModel(
            contacts: [contact(verification: .introSent)]
        )
        #expect(noneReachable.hasReachableContact == false)

        let (reachable, _, _) = makeViewModel(
            contacts: [contact(verification: .reachable)]
        )
        #expect(reachable.hasReachableContact)
    }

    @Test func isReadyToArmRequiresEnabledLabelAndReachable() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(verification: .reachable)],
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        #expect(vm.isReadyToArm)
    }

    @Test func isNotReadyWhenDisabled() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(verification: .reachable)],
            settings: CrashAlertSettings(enabled: false, riderLabel: "Alex")
        )
        #expect(vm.isReadyToArm == false)
    }

    @Test func isNotReadyWithoutReachableContact() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(verification: .introSent)],
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        #expect(vm.isReadyToArm == false)
    }

    @Test func isNotReadyWithoutLabel() {
        let (vm, _, _) = makeViewModel(
            contacts: [contact(verification: .reachable)],
            settings: CrashAlertSettings(enabled: true, riderLabel: nil)
        )
        #expect(vm.isReadyToArm == false)
    }

    // MARK: - Reload

    @Test func reloadPicksUpNewContacts() throws {
        let (vm, contactStore, _) = makeViewModel()
        #expect(vm.contacts.isEmpty)
        try contactStore.add(contact(label: "New"))
        vm.reload()
        #expect(vm.contacts.map(\.label) == ["New"])
    }

    @Test func reloadDoesNotClobberActiveTyping() {
        let (vm, _, _) = makeViewModel(settings: CrashAlertSettings(riderLabel: "Alex"))
        vm.riderLabel = "Al" // simulate mid-edit (persists "Al")
        vm.reload()
        #expect(vm.riderLabel == "Al")
    }

    // MARK: - Nav hooks

    @Test func addContactInvokesHook() {
        let (vm, _, _) = makeViewModel()
        var called = false
        vm.onAddContact = { called = true }
        vm.addContact()
        #expect(called)
    }

    @Test func editContactInvokesHookWithContact() {
        let (vm, _, _) = makeViewModel()
        let target = contact(label: "Mom")
        var received: EmergencyContact?
        vm.onEditContact = { received = $0 }
        vm.editContact(target)
        #expect(received?.id == target.id)
    }
}
