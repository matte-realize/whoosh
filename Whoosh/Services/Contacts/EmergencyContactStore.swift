import Foundation

/// Typed errors from an `EmergencyContactStore` (spec Requirement 2.2, 2.7).
///
/// `contactLimitReached` is thrown when adding would exceed the configured
/// maximum (default 3, cost/abuse control, Requirement 2.2). `storageFailure`
/// wraps a backing-store error (for example a Keychain failure); callers that
/// want the degradation rule "treat a read error as no contacts" (design
/// "Error and degradation handling") use `contactsOrEmpty()` instead of
/// `contacts()`.
enum ContactStoreError: Error, Equatable {
    /// Adding another contact would exceed `maxContacts`.
    case contactLimitReached(max: Int)
    /// The backing store could not complete the operation (e.g. Keychain).
    case storageFailure
}

/// Abstraction over emergency-contact storage (spec Requirement 2.10).
///
/// Contacts live **on the device only**, in the Keychain
/// (`AfterFirstUnlockThisDeviceOnly`), never in SwiftData, UserDefaults, logs,
/// or iCloud (Requirement 2.7). The concrete `KeychainEmergencyContactStore`
/// is the only type allowed to touch Keychain APIs; `InMemoryEmergencyContactStore`
/// backs unit tests and SwiftUI previews.
///
/// The store enforces the max-contacts limit and the "editing a number resets
/// verification" rule (Requirement 2.6) so the invariants hold regardless of the
/// caller. A `read` error is surfaced as a throw by `contacts()`; callers that
/// must degrade to "no contacts" (disarming the feature) use `contactsOrEmpty()`.
///
/// Implementations run on the main actor in this project (default MainActor
/// isolation), consistent with the other stores and repositories.
@MainActor
protocol EmergencyContactStore {
    /// The stored contacts, in insertion order. Throws `storageFailure` if the
    /// backing store cannot be read.
    func contacts() throws -> [EmergencyContact]

    /// The stored contacts, or an empty list if the backing store cannot be
    /// read. Used by arming so a Keychain error disables the feature instead of
    /// crashing (design "Error and degradation handling"; Requirement 2.7).
    func contactsOrEmpty() -> [EmergencyContact]

    /// Add a contact. Throws `contactLimitReached` if the store already holds
    /// `maxContacts` (Requirement 2.2). Adding an id that already exists updates
    /// it (same semantics as `update`).
    func add(_ contact: EmergencyContact) throws

    /// Update an existing contact by id. If the number changed, verification is
    /// reset to `unverified` (Requirement 2.6). Updating a missing id is a safe
    /// no-op.
    func update(_ contact: EmergencyContact) throws

    /// Remove the contact with the given id (real deletion from secure storage,
    /// Requirement 2.6). Removing a missing id is a safe no-op.
    func remove(id: UUID) throws

    /// Remove every stored contact (used by the "Delete my contacts" offer on
    /// consent revocation, Requirement 3.7).
    func removeAll() throws

    /// Purge any orphaned contact items left by a previous install (Keychain
    /// items can outlive app deletion). A no-op unless this is a fresh install
    /// as reported by the injected marker store (Requirement 2.8).
    func purgeOrphansIfFreshInstall() throws
}
