import Foundation
import OSLog
import Security

/// Keychain-backed `EmergencyContactStore` — the **only** file in the app
/// allowed to use Keychain `SecItem` APIs (spec Requirement 2.7, enforced by
/// `scripts/privacy-check.sh`).
///
/// All contacts are stored as a **single JSON blob** in one generic-password
/// item, with:
/// - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable when the
///   phone is locked after first unlock, and kept off backups and other devices,
/// - `kSecAttrSynchronizable = false` — never synced to iCloud Keychain.
///
/// Because Keychain items can **outlive app deletion** (design iOS investigation
/// #9), `purgeOrphansIfFreshInstall()` deletes the item on the first launch
/// after a fresh install, using an injected `FreshInstallMarkerStore` kept in
/// app-container storage (which *is* removed with the app).
///
/// Degradation rule (design "Error and degradation handling"): a Keychain read
/// error is treated as **no contacts** by `contactsOrEmpty()` so the feature
/// disarms instead of crashing; `contacts()` surfaces the error as a throw so
/// setup UI can show it. No full number ever leaves this type except in the
/// encrypted blob.
@MainActor
final class KeychainEmergencyContactStore: EmergencyContactStore {
    /// Default Keychain service name for the single contacts item.
    static let defaultService = "com.whoosh.app.emergencyContacts"
    /// A stable account value for the single item.
    static let account = "contacts"

    private let service: String
    private let maxContacts: Int
    private let markerStore: FreshInstallMarkerStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let logger = Logger(
        subsystem: "com.whoosh.app",
        category: "KeychainEmergencyContactStore"
    )

    /// - Parameters:
    ///   - service: Keychain service name. Tests pass a unique name so runs are
    ///     isolated and cleanable.
    ///   - maxContacts: the enforced maximum (default 3, Requirement 2.2).
    ///   - markerStore: the fresh-install marker used by orphan purge.
    init(
        service: String = defaultService,
        maxContacts: Int = CrashResponseTuning().maxContacts,
        markerStore: FreshInstallMarkerStore
    ) {
        self.service = service
        self.maxContacts = maxContacts
        self.markerStore = markerStore
    }

    func contacts() throws -> [EmergencyContact] {
        try readContacts()
    }

    func contactsOrEmpty() -> [EmergencyContact] {
        // A read error disarms the feature rather than crashing (Requirement 2.7).
        (try? readContacts()) ?? []
    }

    func add(_ contact: EmergencyContact) throws {
        var current = try readContacts()
        if let index = current.firstIndex(where: { $0.id == contact.id }) {
            current[index] = contact
        } else {
            guard current.count < maxContacts else {
                throw ContactStoreError.contactLimitReached(max: maxContacts)
            }
            current.append(contact)
        }
        try writeContacts(current)
    }

    func update(_ contact: EmergencyContact) throws {
        var current = try readContacts()
        guard let index = current.firstIndex(where: { $0.id == contact.id }) else {
            return // updating a missing id is a safe no-op
        }
        // Editing the number resets verification (Requirement 2.6).
        if current[index].e164 != contact.e164 {
            current[index] = contact.changingNumber(to: contact.e164)
        } else {
            current[index] = contact
        }
        try writeContacts(current)
    }

    func remove(id: UUID) throws {
        var current = try readContacts()
        current.removeAll { $0.id == id }
        try writeContacts(current)
    }

    func removeAll() throws {
        try deleteItem()
    }

    func purgeOrphansIfFreshInstall() throws {
        guard !markerStore.hasLaunchedBefore() else { return }
        // First launch after a fresh install: drop any orphaned item, then mark
        // installed so later launches do not purge (Requirement 2.8).
        try deleteItem()
        markerStore.markInstalled()
    }

    // MARK: Keychain primitives

    /// Base query identifying the single contacts item.
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }

    /// Reads and decodes the contacts blob. Returns an empty list when the item
    /// is absent; throws `storageFailure` on an unexpected Keychain status or a
    /// decode failure.
    private func readContacts() throws -> [EmergencyContact] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ContactStoreError.storageFailure
            }
            do {
                return try decoder.decode([EmergencyContact].self, from: data)
            } catch {
                Self.logger.error("Contacts blob failed to decode")
                throw ContactStoreError.storageFailure
            }
        case errSecItemNotFound:
            return []
        default:
            Self.logger.error("Keychain read failed with status \(status, privacy: .public)")
            throw ContactStoreError.storageFailure
        }
    }

    /// Encodes and writes the contacts blob. An empty list deletes the item so
    /// no stale blob remains.
    private func writeContacts(_ contacts: [EmergencyContact]) throws {
        guard !contacts.isEmpty else {
            try deleteItem()
            return
        }
        let data: Data
        do {
            data = try encoder.encode(contacts)
        } catch {
            throw ContactStoreError.storageFailure
        }

        // Try to update an existing item first; if absent, add a new one.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            attributesToUpdate as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                Self.logger.error("Keychain add failed with status \(addStatus, privacy: .public)")
                throw ContactStoreError.storageFailure
            }
        default:
            Self.logger.error("Keychain update failed with status \(updateStatus, privacy: .public)")
            throw ContactStoreError.storageFailure
        }
    }

    /// Deletes the single contacts item; a missing item is a safe no-op.
    private func deleteItem() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            Self.logger.error("Keychain delete failed with status \(status, privacy: .public)")
            throw ContactStoreError.storageFailure
        }
    }
}
