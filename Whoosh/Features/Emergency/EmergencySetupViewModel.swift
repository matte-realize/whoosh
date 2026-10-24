import Foundation
import Observation

/// View model for `EmergencySetupView`, the Emergency setup hub (spec
/// Requirement 2, design "Other screens": the hub pushed from Settings →
/// "Crash alerts").
///
/// Owns the device-local feature settings (rider label, enabled flag) via
/// `CrashAlertSettingsStore` and the contact list via `EmergencyContactStore`.
/// It presents the current contacts with their verification state (icon + text
/// is applied in the view), enforces the rider-label rule, and exposes
/// intents for the view to add/edit a contact.
///
/// Consent (task 17) and the intro/test flow (task 18) are **not** built here.
/// Their entry points are exposed as navigation hooks the composition root
/// wires later; `consentIsWired`/`testIsWired` default to `false` so the view
/// can render the rows as "coming soon" without depending on those tasks.
///
/// UI-framework-free (no SwiftUI import), per the layering table. A Keychain
/// read error degrades to "no contacts" (via `contactsOrEmpty()`), consistent
/// with the design's error-handling rule.
@Observable
@MainActor
final class EmergencySetupViewModel {
    @ObservationIgnored private let contactStore: EmergencyContactStore
    @ObservationIgnored private let settingsStore: CrashAlertSettingsStore
    @ObservationIgnored private let maxContacts: Int

    /// Navigation hooks the composition root wires. Left as clearly-marked
    /// no-ops so task 16 does not depend on consent (task 17) or the test flow
    /// (task 18).
    @ObservationIgnored var onAddContact: () -> Void = {}
    @ObservationIgnored var onEditContact: (EmergencyContact) -> Void = { _ in }
    /// Opens the consent screen (task 17). `nil` until wired.
    @ObservationIgnored var onOpenConsent: (() -> Void)?
    /// Opens the intro/test flow (task 18). `nil` until wired.
    @ObservationIgnored var onOpenTest: (() -> Void)?
    /// Opens the crash alert log (task 22).
    @ObservationIgnored var onOpenLog: () -> Void = {}

    /// Triggers a simulated crash through the real workflow (task 23). Wired by
    /// the composition root to the `DebugCrashSimulator`; a no-op until wired so
    /// the hub does not depend on the detector.
    @ObservationIgnored var onSimulateCrash: () -> Void = {}

    /// The current contacts, most relevant first (insertion order from the store).
    private(set) var contacts: [EmergencyContact] = []
    /// The rider label used in messages (first name or nickname).
    var riderLabel: String {
        didSet { persistRiderLabel() }
    }
    /// Whether the feature is enabled. Off by default (Requirement 1.4).
    private(set) var isEnabled: Bool

    /// Whether the "Developer / demo tools" section is revealed, gating the
    /// "Simulate crash" control (Requirement 19.9). Persisted in settings; off
    /// by default. A demo-mode integration (separate branch) may also drive it.
    var developerToolsEnabled: Bool {
        didSet { persistDeveloperTools() }
    }

    init(
        contactStore: EmergencyContactStore,
        settingsStore: CrashAlertSettingsStore,
        maxContacts: Int = CrashResponseTuning().maxContacts
    ) {
        self.contactStore = contactStore
        self.settingsStore = settingsStore
        self.maxContacts = maxContacts
        let settings = settingsStore.current()
        self.riderLabel = settings.riderLabel ?? ""
        self.isEnabled = settings.enabled
        self.developerToolsEnabled = settings.developerToolsEnabled
        reload()
    }

    // MARK: - Derived state

    /// `true` when another contact can be added (under the max, Requirement 2.2).
    var canAddContact: Bool {
        contacts.count < maxContacts
    }

    /// The remaining number of contacts the rider may add.
    var remainingContactSlots: Int {
        max(0, maxContacts - contacts.count)
    }

    /// `true` once the rider has entered a non-empty label (Requirement 2.9).
    var hasRiderLabel: Bool {
        !riderLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `true` when at least one contact is in the `reachable` state — the only
    /// contacts that receive automatic alerts (Requirement 2.5 / 4.5).
    var hasReachableContact: Bool {
        contacts.contains { $0.verification == .reachable }
    }

    /// Whether the feature is ready to be armed: enabled, a rider label exists,
    /// and at least one reachable contact. Mirrors `CrashArming` inputs so the
    /// hub can show an honest on/off summary (the coordinator is authoritative).
    var isReadyToArm: Bool {
        isEnabled && hasRiderLabel && hasReachableContact
    }

    // MARK: - Intents

    /// Reload the contact list and settings (call when the hub reappears after
    /// adding/editing a contact). A Keychain read error degrades to an empty
    /// list rather than crashing.
    func reload() {
        contacts = contactStore.contactsOrEmpty()
        let settings = settingsStore.current()
        isEnabled = settings.enabled
        // Adopt the stored developer-tools flag without re-triggering a write
        // (the values match, so the didSet persist is a harmless no-op).
        if developerToolsEnabled != settings.developerToolsEnabled {
            developerToolsEnabled = settings.developerToolsEnabled
        }
        // Adopt the stored label only when the field is empty (first load or an
        // external change), so reloading does not clobber active typing with the
        // sanitized value written by `persistRiderLabel`.
        if riderLabel.isEmpty, let stored = settings.riderLabel {
            riderLabel = stored
        }
    }

    /// Request to add a new contact (routes to the editor via the nav hook).
    func addContact() {
        onAddContact()
    }

    /// Request to edit an existing contact.
    func editContact(_ contact: EmergencyContact) {
        onEditContact(contact)
    }

    /// Trigger a simulated crash through the real workflow (demo path, task 23).
    /// Only meaningful while the developer-tools section is revealed; the view
    /// shows the control only then, and this guards it defensively.
    func simulateCrash() {
        guard developerToolsEnabled else { return }
        onSimulateCrash()
    }

    // MARK: - Persistence

    private func persistRiderLabel() {
        var settings = settingsStore.current()
        let trimmed = riderLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sanitize to the GSM-7-safe label charset so what is stored is what a
        // message can carry (Requirement 2.9 / 10.3).
        let sanitized = GSM7Sanitizer.riderLabel(trimmed)
        settings.riderLabel = sanitized.isEmpty ? nil : sanitized
        settingsStore.save(settings)
    }

    private func persistDeveloperTools() {
        var settings = settingsStore.current()
        settings.developerToolsEnabled = developerToolsEnabled
        settingsStore.save(settings)
    }
}
