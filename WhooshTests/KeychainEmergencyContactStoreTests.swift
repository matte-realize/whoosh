import Foundation
import Testing
@testable import Whoosh

/// Tests for `KeychainEmergencyContactStore` (crash-response task 11,
/// Requirements 2.7, 2.8, 16.1). Each test uses a **unique service name** so
/// runs are isolated, and cleans up the Keychain item afterward via a
/// `removeAll()` in a `defer`. Runs in the app test host, where the Keychain is
/// available.
@MainActor
struct KeychainEmergencyContactStoreTests {
    private func contact(
        _ id: UUID = UUID(),
        label: String = "Mom",
        e164: String = "+16175550123",
        verification: ContactVerification = .unverified
    ) -> EmergencyContact {
        EmergencyContact(id: id, label: label, e164: e164, verification: verification)
    }

    /// A store with a unique service name and a marker that reports "launched
    /// before" so orphan purge does not interfere with ordinary tests.
    private func makeStore(
        hasLaunchedBefore: Bool = true,
        contacts: [EmergencyContact] = []
    ) throws -> KeychainEmergencyContactStore {
        let service = "com.whoosh.test.contacts.\(UUID().uuidString)"
        let marker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: hasLaunchedBefore)
        let store = KeychainEmergencyContactStore(service: service, markerStore: marker)
        // Start clean (no orphan from a prior run with the same name — unlikely
        // given the UUID, but defensive).
        try store.removeAll()
        for contact in contacts {
            try store.add(contact)
        }
        return store
    }

    // MARK: round-trip

    @Test func addThenReadRoundTrips() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        let a = contact(label: "A", e164: "+16175550111")
        let b = contact(label: "B", e164: "+16175550112")
        try store.add(a)
        try store.add(b)
        #expect(try store.contacts().map(\.label) == ["A", "B"])
        #expect(try store.contacts().map(\.e164) == ["+16175550111", "+16175550112"])
    }

    @Test func emptyStoreReadsEmpty() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        #expect(try store.contacts().isEmpty)
        #expect(store.contactsOrEmpty().isEmpty)
    }

    // MARK: limit (Requirement 2.2)

    @Test func addRefusesBeyondMaxContacts() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        try store.add(contact(label: "A"))
        try store.add(contact(label: "B"))
        try store.add(contact(label: "C"))
        #expect(throws: ContactStoreError.contactLimitReached(max: 3)) {
            try store.add(contact(label: "D"))
        }
        #expect(try store.contacts().count == 3)
    }

    // MARK: update + verification reset (Requirement 2.6)

    @Test func updatingNumberResetsVerification() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        let id = UUID()
        try store.add(contact(id, e164: "+16175550123", verification: .reachable))
        try store.update(contact(id, e164: "+16175550999", verification: .reachable))
        let stored = try store.contacts().first
        #expect(stored?.e164 == "+16175550999")
        #expect(stored?.verification == .unverified)
    }

    @Test func updatingLabelOnlyPreservesVerification() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        let id = UUID()
        try store.add(contact(id, label: "Mom", e164: "+16175550123", verification: .reachable))
        try store.update(
            EmergencyContact(id: id, label: "Mum", e164: "+16175550123", verification: .reachable)
        )
        let stored = try store.contacts().first
        #expect(stored?.label == "Mum")
        #expect(stored?.verification == .reachable)
    }

    // MARK: remove / removeAll

    @Test func removeDeletesByID() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        let keep = contact(label: "keep", e164: "+16175550111")
        let drop = contact(label: "drop", e164: "+16175550112")
        try store.add(keep)
        try store.add(drop)
        try store.remove(id: drop.id)
        #expect(try store.contacts().map(\.label) == ["keep"])
    }

    @Test func removeAllClearsItem() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        try store.add(contact(label: "A"))
        try store.add(contact(label: "B"))
        try store.removeAll()
        #expect(try store.contacts().isEmpty)
    }

    @Test func removeLastContactLeavesEmptyReadable() throws {
        let store = try makeStore()
        defer { try? store.removeAll() }
        let only = contact(label: "only")
        try store.add(only)
        try store.remove(id: only.id)
        // Removing the last contact deletes the item; reading returns empty,
        // not an error.
        #expect(try store.contacts().isEmpty)
    }

    // MARK: fresh-install orphan purge (Requirement 2.8)

    @Test func purgeOnFreshInstallClearsOrphanedContacts() throws {
        // First "install": write a contact, then simulate it being left behind.
        let service = "com.whoosh.test.contacts.\(UUID().uuidString)"
        let firstMarker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: true)
        let firstStore = KeychainEmergencyContactStore(service: service, markerStore: firstMarker)
        try firstStore.removeAll()
        defer { try? firstStore.removeAll() }
        try firstStore.add(contact(label: "orphan"))
        #expect(try firstStore.contacts().count == 1)

        // Fresh install: new marker reports "not launched before"; the orphaned
        // Keychain item (same service name) must be purged on first launch.
        let freshMarker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: false)
        let freshStore = KeychainEmergencyContactStore(service: service, markerStore: freshMarker)
        try freshStore.purgeOrphansIfFreshInstall()
        #expect(try freshStore.contacts().isEmpty)
        #expect(freshMarker.hasLaunchedBefore())
    }

    @Test func purgeIsNoOpWhenNotFreshInstall() throws {
        let service = "com.whoosh.test.contacts.\(UUID().uuidString)"
        let marker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: true)
        let store = KeychainEmergencyContactStore(service: service, markerStore: marker)
        try store.removeAll()
        defer { try? store.removeAll() }
        try store.add(contact(label: "keep"))
        try store.purgeOrphansIfFreshInstall()
        #expect(try store.contacts().map(\.label) == ["keep"])
    }

    // MARK: unique service isolation

    @Test func differentServiceNamesAreIsolated() throws {
        let storeA = try makeStore(contacts: [contact(label: "A")])
        defer { try? storeA.removeAll() }
        let storeB = try makeStore()
        defer { try? storeB.removeAll() }
        // storeB uses a different unique service name, so it sees none of A.
        #expect(try storeA.contacts().count == 1)
        #expect(try storeB.contacts().isEmpty)
    }
}
