import Foundation
import Testing
@testable import Whoosh

/// Tests for the consent and settings stores (crash-response task 9,
/// Requirements 3.1, 3.6, 3.7). Covers the in-memory fakes and the
/// `UserDefaults` implementations (with an isolated, injected suite), plus the
/// cross-check that a consent version bump disarms the detector via
/// `CrashArming`.
@MainActor
struct ConsentAndSettingsStoreTests {
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// A fresh, isolated `UserDefaults` suite so tests never touch the shared
    /// `.standard` defaults and never collide with each other.
    private func isolatedDefaults() -> UserDefaults {
        let suite = "whoosh.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: ConsentStore — in-memory

    @Test func inMemoryConsentRecordAndRevoke() {
        let store = InMemoryConsentStore()
        #expect(store.current() == nil)
        store.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)
        #expect(store.current()?.version == 1)
        #expect(store.current()?.acknowledgedNotGuaranteed == true)
        store.revoke()
        #expect(store.current() == nil)
    }

    // MARK: ConsentStore — UserDefaults (injected suite)

    @Test func userDefaultsConsentPersistsUnderInjectedSuite() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsConsentStore(defaults: defaults)
        store.record(version: 2, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)

        // A second store over the same defaults reads the same record back.
        let reopened = UserDefaultsConsentStore(defaults: defaults)
        #expect(reopened.current()?.version == 2)
        #expect(reopened.current()?.acceptedAt == Self.t0)
    }

    @Test func userDefaultsConsentRevokeClearsRecord() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsConsentStore(defaults: defaults)
        store.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)
        store.revoke()
        #expect(UserDefaultsConsentStore(defaults: defaults).current() == nil)
    }

    @Test func absentConsentIsNil() {
        let store = UserDefaultsConsentStore(defaults: isolatedDefaults())
        #expect(store.current() == nil)
    }

    // MARK: consent currency / version bump

    @Test func consentNotCurrentWithoutAcknowledgement() {
        let record = ConsentRecord(version: 1, acceptedAt: Self.t0, acknowledgedNotGuaranteed: false)
        #expect(!record.isCurrent(minimumVersion: 1))
    }

    @Test func consentNotCurrentBelowMinimumVersion() {
        let record = ConsentRecord(version: 1, acceptedAt: Self.t0, acknowledgedNotGuaranteed: true)
        // A material text change bumped the minimum to 2 (Requirement 3.6).
        #expect(!record.isCurrent(minimumVersion: 2))
    }

    /// A consent version bump (minimum raised above the stored version) must
    /// disarm the detector via `CrashArming` (Requirement 3.6, 5.4).
    @Test func consentVersionBumpDisarmsViaCrashArming() {
        let store = InMemoryConsentStore()
        store.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)

        // Current consent (v1, min 1) ⇒ armed.
        let armedInput = CrashArming.Input(
            rideState: .recording,
            enabled: true,
            consentCurrent: store.current()?.isCurrent(minimumVersion: 1) ?? false,
            riderLabelPresent: true,
            reachableContactCount: 1
        )
        #expect(CrashArming.isArmed(armedInput))

        // Version bump to a minimum of 2 ⇒ consent no longer current ⇒ disarmed.
        let disarmedInput = CrashArming.Input(
            rideState: .recording,
            enabled: true,
            consentCurrent: store.current()?.isCurrent(minimumVersion: 2) ?? false,
            riderLabelPresent: true,
            reachableContactCount: 1
        )
        #expect(!CrashArming.isArmed(disarmedInput))
    }

    @Test func revokedConsentDisarmsViaCrashArming() {
        let store = InMemoryConsentStore()
        store.record(version: 1, acknowledgedNotGuaranteed: true, acceptedAt: Self.t0)
        store.revoke()
        let input = CrashArming.Input(
            rideState: .recording,
            enabled: true,
            consentCurrent: store.current()?.isCurrent(minimumVersion: 1) ?? false,
            riderLabelPresent: true,
            reachableContactCount: 1
        )
        #expect(!CrashArming.isArmed(input))
    }

    // MARK: CrashAlertSettingsStore

    @Test func settingsDefaultIsFeatureOn() {
        // Hackathon build default; arming still needs consent and a contact.
        let store = InMemoryCrashAlertSettingsStore()
        #expect(store.current().enabled == true)
        #expect(store.current().riderLabel == nil)
    }

    @Test func settingsPersistUnderInjectedSuite() {
        let defaults = isolatedDefaults()
        let store = UserDefaultsCrashAlertSettingsStore(defaults: defaults)
        var settings = CrashAlertSettings()
        settings.enabled = true
        settings.riderLabel = "Alex"
        settings.developerToolsEnabled = true
        store.save(settings)

        let reopened = UserDefaultsCrashAlertSettingsStore(defaults: defaults)
        #expect(reopened.current().enabled)
        #expect(reopened.current().riderLabel == "Alex")
        #expect(reopened.current().developerToolsEnabled)
    }

    @Test func absentSettingsReadsDefaultOff() {
        let store = UserDefaultsCrashAlertSettingsStore(defaults: isolatedDefaults())
        #expect(store.current() == CrashAlertSettings())
    }

    // MARK: FreshInstallMarkerStore

    @Test func userDefaultsMarkerStartsUnlaunchedThenMarks() {
        let defaults = isolatedDefaults()
        let marker = UserDefaultsFreshInstallMarkerStore(defaults: defaults)
        #expect(!marker.hasLaunchedBefore())
        marker.markInstalled()
        #expect(UserDefaultsFreshInstallMarkerStore(defaults: defaults).hasLaunchedBefore())
    }
}
