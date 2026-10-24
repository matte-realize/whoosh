import Foundation
import Testing
@testable import Whoosh

/// Tests for `ConsentViewModel` (crash-response task 17, Requirement 1 and 3).
///
/// Verify: version gating (a stored version below the current one is not
/// current and re-acceptance is required), the two controls (data-use consent +
/// not-a-guarantee acknowledgement) must both be on to enable, enabling records
/// consent + turns the feature on + requests notification authorization, the
/// live message preview comes from the shared `CrashMessageBuilder`, and the
/// revoke path clears consent, disables the feature, asks the coordinator to
/// cancel a queued alert, and offers to delete contacts.
@MainActor
struct ConsentViewModelTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeViewModel(
        consent: ConsentRecord? = nil,
        settings: CrashAlertSettings = CrashAlertSettings(riderLabel: "Alex"),
        contacts: [EmergencyContact] = [],
        currentVersion: Int = 1,
        authorizationGranted: Bool = true
    ) -> (
        vm: ConsentViewModel,
        consentStore: InMemoryConsentStore,
        settingsStore: InMemoryCrashAlertSettingsStore,
        contactStore: InMemoryEmergencyContactStore,
        scheduler: FakeCrashNotificationScheduler
    ) {
        let consentStore = InMemoryConsentStore(consent: consent)
        let settingsStore = InMemoryCrashAlertSettingsStore(settings: settings)
        let contactStore = InMemoryEmergencyContactStore(contacts: contacts)
        let scheduler = FakeCrashNotificationScheduler(authorizationGranted: authorizationGranted)
        let vm = ConsentViewModel(
            consentStore: consentStore,
            settingsStore: settingsStore,
            contactStore: contactStore,
            scheduler: scheduler,
            clock: TestClock(now: t0),
            currentConsentVersion: currentVersion
        )
        return (vm, consentStore, settingsStore, contactStore, scheduler)
    }

    // MARK: - Version gating (Requirement 3.6)

    @Test func noPriorConsentIsNotCurrent() {
        let (vm, _, _, _, _) = makeViewModel()
        #expect(vm.isConsentCurrent == false)
        #expect(vm.needsReacceptance == false) // never accepted, not a bump
    }

    @Test func currentVersionConsentIsCurrent() {
        let (vm, _, _, _, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            currentVersion: 1
        )
        #expect(vm.isConsentCurrent)
        #expect(vm.needsReacceptance == false)
    }

    @Test func outdatedVersionNeedsReacceptance() {
        let (vm, _, _, _, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            currentVersion: 2
        )
        #expect(vm.isConsentCurrent == false)
        #expect(vm.needsReacceptance)
    }

    // MARK: - Two controls required (Requirement 1.2, 3.1)

    @Test func enableRequiresBothControls() async {
        // Crash alerts default on in the hackathon build; start from off to
        // prove enable() needs both controls.
        let (vm, consentStore, settingsStore, _, _) = makeViewModel(
            settings: CrashAlertSettings(enabled: false, riderLabel: "Alex")
        )
        // Only data-use consent, no acknowledgement.
        vm.dataUseConsented = true
        vm.acknowledgedNotGuaranteed = false
        #expect(vm.canEnable == false)
        await vm.enable()
        #expect(consentStore.current() == nil)
        #expect(settingsStore.current().enabled == false)

        // Only acknowledgement, no data-use consent.
        vm.dataUseConsented = false
        vm.acknowledgedNotGuaranteed = true
        #expect(vm.canEnable == false)
    }

    @Test func enableRequiresRiderLabel() {
        let (vm, _, _, _, _) = makeViewModel(settings: CrashAlertSettings(riderLabel: nil))
        vm.dataUseConsented = true
        vm.acknowledgedNotGuaranteed = true
        #expect(vm.canEnable == false)
    }

    // MARK: - Enabling records consent, enables feature, requests auth

    @Test func enableRecordsConsentEnablesAndRequestsAuthorization() async {
        let (vm, consentStore, settingsStore, _, scheduler) = makeViewModel(currentVersion: 3)
        vm.dataUseConsented = true
        vm.acknowledgedNotGuaranteed = true
        #expect(vm.canEnable)
        await vm.enable()

        let record = consentStore.current()
        #expect(record?.version == 3)
        #expect(record?.acknowledgedNotGuaranteed == true)
        #expect(record?.acceptedAt == t0)
        #expect(settingsStore.current().enabled)
        #expect(scheduler.authorizationRequestCount == 1)
        #expect(vm.isConsentCurrent)
        #expect(vm.isEnabled)
    }

    @Test func authorizationDenialStillEnablesFeature() async {
        // A denied notification permission is not an error: the feature still
        // turns on, only the backup prompt is unavailable (design O1(c)).
        let (vm, _, settingsStore, _, scheduler) = makeViewModel(authorizationGranted: false)
        vm.dataUseConsented = true
        vm.acknowledgedNotGuaranteed = true
        await vm.enable()
        #expect(settingsStore.current().enabled)
        #expect(scheduler.authorizationRequestCount == 1)
        #expect(vm.notificationsAuthorized == false)
    }

    @Test func enablePreloadsControlsWhenAlreadyCurrent() {
        // Opening the screen while consent is already current pre-checks both
        // controls so the rider sees their prior choice.
        let (vm, _, _, _, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex"),
            currentVersion: 1
        )
        #expect(vm.dataUseConsented)
        #expect(vm.acknowledgedNotGuaranteed)
        #expect(vm.isEnabled)
    }

    // MARK: - Live message preview (Requirement 3.5)

    @Test func messagePreviewMatchesBuilderCrashAlert() {
        let (vm, _, _, _, _) = makeViewModel(settings: CrashAlertSettings(riderLabel: "Alex"))
        let expected = CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: "Alex",
            detectedAt: vm.previewDetectedAt,
            utcOffsetMinutes: vm.previewUtcOffsetMinutes,
            location: vm.previewLocation,
            delayedSeconds: 0,
            now: vm.previewDetectedAt
        ).text
        #expect(vm.messagePreview == expected)
        // The preview must contain the honest non-guarantee statement.
        #expect(vm.messagePreview.contains("an injury has NOT been confirmed"))
    }

    @Test func messagePreviewUsesFallbackLabelWhenEmpty() {
        let (vm, _, _, _, _) = makeViewModel(settings: CrashAlertSettings(riderLabel: nil))
        // With no rider label yet, the preview still renders a sample so the
        // rider can read the exact wording.
        #expect(!vm.messagePreview.isEmpty)
        #expect(vm.messagePreview.contains("WHOOSH ALERT"))
    }

    // MARK: - Revoke (Requirement 3.7)

    @Test func revokeClearsConsentDisablesAndOffersDeleteContacts() {
        let (vm, consentStore, settingsStore, _, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex")
        )
        var coordinatorNotified = false
        vm.onConsentRevoked = { coordinatorNotified = true }

        vm.revoke()

        #expect(consentStore.current() == nil)
        #expect(settingsStore.current().enabled == false)
        #expect(coordinatorNotified) // coordinator disarms + cancels queued alert
        #expect(vm.isOfferingContactDeletion) // "Delete my contacts" offer shown
        #expect(vm.isEnabled == false)
        #expect(vm.dataUseConsented == false)
        #expect(vm.acknowledgedNotGuaranteed == false)
    }

    @Test func deleteContactsRemovesAllAndDismissesOffer() throws {
        let (vm, _, _, contactStore, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex"),
            contacts: [EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123")]
        )
        vm.revoke()
        #expect(vm.isOfferingContactDeletion)
        vm.deleteContacts()
        #expect(try contactStore.contacts().isEmpty)
        #expect(vm.isOfferingContactDeletion == false)
    }

    @Test func keepContactsDismissesOfferWithoutDeleting() throws {
        let (vm, _, _, contactStore, _) = makeViewModel(
            consent: ConsentRecord(version: 1, acceptedAt: t0, acknowledgedNotGuaranteed: true),
            settings: CrashAlertSettings(enabled: true, riderLabel: "Alex"),
            contacts: [EmergencyContact(id: UUID(), label: "Mom", e164: "+16175550123")]
        )
        vm.revoke()
        vm.keepContacts()
        #expect(try contactStore.contacts().count == 1)
        #expect(vm.isOfferingContactDeletion == false)
    }
}
