import Foundation
import Observation

/// View model for `ConsentView`, the crash-alert consent and disclosure screen
/// (spec Requirement 1 and 3, task 17).
///
/// Owns the versioned, revocable consent record (`ConsentStore`) and the device
/// feature toggle (`CrashAlertSettingsStore`). The screen presents, in plain
/// language, exactly what is and is not sent, the precise-location /
/// not-privacy-zone-trimmed notice, the SMS-not-encrypted notice, the STOP
/// explanation, and the foreground-only limitation. It renders a **live message
/// preview** from the shared `CrashMessageBuilder` so the rider reads the exact
/// wording a contact would receive (Requirement 3.5).
///
/// Enabling requires **two** separate controls (Requirement 1.2 / 3.1): a
/// data-use consent and a not-a-guarantee acknowledgement. On enable the model
/// records consent at the current version, turns the feature on, and requests
/// notification authorization (only here, after the in-app explanation —
/// Requirement 13.3). Consent can be revoked at any time (Requirement 3.7):
/// revoking clears the record, disables the feature, asks the coordinator to
/// disarm and cancel any queued unsent alert (via `onConsentRevoked`), and
/// offers "Delete my contacts".
///
/// A material message-text change bumps `currentConsentVersion`; a stored record
/// below it is not current and the rider is asked again (Requirement 3.6).
///
/// UI-framework-free (no SwiftUI import), per the layering table. Copy lives in
/// the view; this model exposes only state and intents so it can be unit-tested
/// without UI.
@Observable
@MainActor
final class ConsentViewModel {
    @ObservationIgnored private let consentStore: ConsentStore
    @ObservationIgnored private let settingsStore: CrashAlertSettingsStore
    @ObservationIgnored private let contactStore: EmergencyContactStore
    @ObservationIgnored private let scheduler: CrashNotificationScheduler
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let currentConsentVersion: Int

    /// Called when consent is revoked so the composition root can ask the
    /// `CrashResponseCoordinator` to disarm and cancel any queued unsent alert
    /// (Requirement 3.7). `nil` until wired.
    @ObservationIgnored var onConsentRevoked: (() -> Void)?

    // MARK: Rider-facing controls (Requirement 1.2 / 3.1)

    /// The rider agrees to the described data use (what is sent, to whom, how).
    var dataUseConsented: Bool
    /// The rider acknowledges Whoosh is not a guaranteed emergency service.
    var acknowledgedNotGuaranteed: Bool

    // MARK: Derived / observable state

    /// Whether the feature toggle is currently on.
    private(set) var isEnabled: Bool
    /// Whether notification authorization was granted when last requested. The
    /// feature works either way; a denial just removes the backup prompt.
    private(set) var notificationsAuthorized = false
    /// Whether the "Delete my contacts" offer is being shown after a revoke.
    private(set) var isOfferingContactDeletion = false

    init(
        consentStore: ConsentStore,
        settingsStore: CrashAlertSettingsStore,
        contactStore: EmergencyContactStore,
        scheduler: CrashNotificationScheduler,
        clock: Clock,
        currentConsentVersion: Int = CrashMessageBuilder.templateVersion
    ) {
        self.consentStore = consentStore
        self.settingsStore = settingsStore
        self.contactStore = contactStore
        self.scheduler = scheduler
        self.clock = clock
        self.currentConsentVersion = currentConsentVersion

        let settings = settingsStore.current()
        self.isEnabled = settings.enabled

        // Pre-check both controls when consent is already current so the rider
        // sees their prior choice.
        let current = consentStore.current()?.isCurrent(minimumVersion: currentConsentVersion) ?? false
        self.dataUseConsented = current
        self.acknowledgedNotGuaranteed = current
    }

    // MARK: - Version gating (Requirement 3.6)

    /// Whether the stored consent meets the current version and acknowledgement.
    var isConsentCurrent: Bool {
        consentStore.current()?.isCurrent(minimumVersion: currentConsentVersion) ?? false
    }

    /// Whether a previously-accepted consent is now below the current version
    /// and must be re-accepted (a material text change bumped the version).
    var needsReacceptance: Bool {
        guard let record = consentStore.current() else { return false }
        return !record.isCurrent(minimumVersion: currentConsentVersion)
    }

    /// Whether the rider has entered a label (required before enabling,
    /// Requirement 2.9).
    var hasRiderLabel: Bool {
        (settingsStore.current().riderLabel?.isEmpty == false)
    }

    /// Whether both controls are on and a rider label exists, so the feature can
    /// be enabled.
    var canEnable: Bool {
        dataUseConsented && acknowledgedNotGuaranteed && hasRiderLabel
    }

    // MARK: - Enable (record consent, turn on, request authorization)

    /// Record consent at the current version, enable the feature, and request
    /// notification authorization (only here, after the in-app explanation).
    /// A no-op unless both controls are on and a label exists.
    func enable() async {
        guard canEnable else { return }
        consentStore.record(
            version: currentConsentVersion,
            acknowledgedNotGuaranteed: acknowledgedNotGuaranteed,
            acceptedAt: clock.now()
        )
        var settings = settingsStore.current()
        settings.enabled = true
        settingsStore.save(settings)
        isEnabled = true

        // Request notification authorization only when the rider enables alerts
        // (Requirement 13.3). A denial is not an error.
        notificationsAuthorized = await scheduler.requestAuthorizationIfNeeded()
    }

    // MARK: - Revoke (Requirement 3.7)

    /// Revoke consent: clear the record, disable the feature immediately, ask
    /// the coordinator to disarm and cancel any queued unsent alert, and offer
    /// to delete the contacts.
    func revoke() {
        consentStore.revoke()
        var settings = settingsStore.current()
        settings.enabled = false
        settingsStore.save(settings)
        isEnabled = false
        dataUseConsented = false
        acknowledgedNotGuaranteed = false
        onConsentRevoked?()
        isOfferingContactDeletion = true
    }

    /// Delete every contact (the "Delete my contacts" offer) and dismiss it.
    func deleteContacts() {
        try? contactStore.removeAll()
        isOfferingContactDeletion = false
    }

    /// Keep the contacts and dismiss the offer.
    func keepContacts() {
        isOfferingContactDeletion = false
    }

    // MARK: - Live message preview (Requirement 3.5)

    /// A fixed sample detection instant for the preview (locale-independent).
    let previewDetectedAt = Date(timeIntervalSince1970: 1_761_327_667) // 2025-10-24T17:41:07Z
    /// A fixed sample UTC offset for the preview (−4 h, US Eastern DST).
    let previewUtcOffsetMinutes = -240
    /// A fixed sample current-location snapshot for the preview.
    let previewLocation = LocationSnapshot(
        latitude: 42.36012,
        longitude: -71.05888,
        horizontalAccuracy: 12,
        fixTime: Date(timeIntervalSince1970: 1_761_327_667),
        status: .current
    )

    /// The exact `crash_alert` text a contact would receive, rendered by the
    /// shared builder with the rider's label (or a sample when none is set).
    var messagePreview: String {
        let label = settingsStore.current().riderLabel ?? "Alex"
        return CrashMessageBuilder.build(
            kind: .crashAlert,
            riderLabel: label,
            detectedAt: previewDetectedAt,
            utcOffsetMinutes: previewUtcOffsetMinutes,
            location: previewLocation,
            delayedSeconds: 0,
            now: previewDetectedAt
        ).text
    }
}
