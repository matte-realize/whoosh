import Foundation

/// In-memory `EmergencyContactStore` for unit tests and SwiftUI previews.
///
/// Keeps contacts in insertion order, enforces the max-contacts limit, and
/// applies the "editing a number resets verification" rule (Requirement 2.6) so
/// it behaves exactly like the Keychain implementation minus persistence. An
/// optional injected `markerStore` lets `purgeOrphansIfFreshInstall()` be tested
/// without a real Keychain.
///
/// Lives under `Services/Contacts/` (not the test target) so the composition
/// root and previews can inject it; tests reach it via `@testable import`.
@MainActor
final class InMemoryEmergencyContactStore: EmergencyContactStore {
    private var ordered: [EmergencyContact]
    private let maxContacts: Int
    private let markerStore: FreshInstallMarkerStore

    init(
        contacts: [EmergencyContact] = [],
        maxContacts: Int = CrashResponseTuning().maxContacts,
        markerStore: FreshInstallMarkerStore = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: true)
    ) {
        self.ordered = contacts
        self.maxContacts = maxContacts
        self.markerStore = markerStore
    }

    func contacts() throws -> [EmergencyContact] {
        ordered
    }

    func contactsOrEmpty() -> [EmergencyContact] {
        ordered
    }

    func add(_ contact: EmergencyContact) throws {
        if let index = ordered.firstIndex(where: { $0.id == contact.id }) {
            ordered[index] = contact
            return
        }
        guard ordered.count < maxContacts else {
            throw ContactStoreError.contactLimitReached(max: maxContacts)
        }
        ordered.append(contact)
    }

    func update(_ contact: EmergencyContact) throws {
        guard let index = ordered.firstIndex(where: { $0.id == contact.id }) else {
            return // updating a missing id is a safe no-op
        }
        // Editing the number resets verification (Requirement 2.6).
        if ordered[index].e164 != contact.e164 {
            ordered[index] = contact.changingNumber(to: contact.e164)
        } else {
            ordered[index] = contact
        }
    }

    func remove(id: UUID) throws {
        ordered.removeAll { $0.id == id }
    }

    func removeAll() throws {
        ordered.removeAll()
    }

    func purgeOrphansIfFreshInstall() throws {
        guard !markerStore.hasLaunchedBefore() else { return }
        ordered.removeAll()
        markerStore.markInstalled()
    }
}
