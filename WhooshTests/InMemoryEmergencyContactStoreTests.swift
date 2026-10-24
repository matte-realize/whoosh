import Foundation
import Testing
@testable import Whoosh

/// Tests for the in-memory `EmergencyContactStore` (crash-response task 9,
/// Requirements 2.2, 2.6, 2.8, 2.10). The same behavioral contract is expected
/// of `KeychainEmergencyContactStore` (see `KeychainEmergencyContactStoreTests`).
@MainActor
struct InMemoryEmergencyContactStoreTests {
    private static func contact(
        _ id: UUID = UUID(),
        label: String = "Mom",
        e164: String = "+16175550123",
        verification: ContactVerification = .unverified
    ) -> EmergencyContact {
        EmergencyContact(id: id, label: label, e164: e164, verification: verification)
    }

    // MARK: add / limit (Requirement 2.2)

    @Test func addAppendsInOrder() throws {
        let store = InMemoryEmergencyContactStore()
        let a = Self.contact(label: "A")
        let b = Self.contact(label: "B")
        try store.add(a)
        try store.add(b)
        #expect(try store.contacts().map(\.label) == ["A", "B"])
    }

    @Test func addRefusesBeyondMaxContacts() throws {
        let store = InMemoryEmergencyContactStore(maxContacts: 3)
        try store.add(Self.contact(label: "A"))
        try store.add(Self.contact(label: "B"))
        try store.add(Self.contact(label: "C"))
        #expect(throws: ContactStoreError.contactLimitReached(max: 3)) {
            try store.add(Self.contact(label: "D"))
        }
        #expect(try store.contacts().count == 3)
    }

    @Test func addExistingIDUpdatesInsteadOfLimiting() throws {
        let store = InMemoryEmergencyContactStore(maxContacts: 1)
        let id = UUID()
        try store.add(Self.contact(id, label: "A"))
        // Re-adding the same id updates it and does not hit the limit.
        try store.add(Self.contact(id, label: "A2"))
        #expect(try store.contacts().count == 1)
        #expect(try store.contacts().first?.label == "A2")
    }

    // MARK: update + verification reset (Requirement 2.6)

    @Test func updatingNumberResetsVerification() throws {
        let store = InMemoryEmergencyContactStore()
        let id = UUID()
        try store.add(Self.contact(id, e164: "+16175550123", verification: .reachable))
        var edited = Self.contact(id, e164: "+16175550999", verification: .reachable)
        edited.label = "Mom"
        try store.update(edited)
        let stored = try store.contacts().first
        #expect(stored?.e164 == "+16175550999")
        #expect(stored?.verification == .unverified)
    }

    @Test func updatingLabelOnlyPreservesVerification() throws {
        let store = InMemoryEmergencyContactStore()
        let id = UUID()
        try store.add(Self.contact(id, label: "Mom", e164: "+16175550123", verification: .reachable))
        let edited = EmergencyContact(
            id: id,
            label: "Mum",
            e164: "+16175550123",
            verification: .reachable
        )
        try store.update(edited)
        let stored = try store.contacts().first
        #expect(stored?.label == "Mum")
        #expect(stored?.verification == .reachable)
    }

    @Test func updatingMissingIDIsSafeNoOp() throws {
        let store = InMemoryEmergencyContactStore()
        try store.add(Self.contact(label: "A"))
        try store.update(Self.contact(label: "ghost"))
        #expect(try store.contacts().count == 1)
        #expect(try store.contacts().first?.label == "A")
    }

    // MARK: remove / removeAll (Requirement 2.6, 3.7)

    @Test func removeDeletesByID() throws {
        let store = InMemoryEmergencyContactStore()
        let keep = Self.contact(label: "keep")
        let drop = Self.contact(label: "drop")
        try store.add(keep)
        try store.add(drop)
        try store.remove(id: drop.id)
        #expect(try store.contacts().map(\.label) == ["keep"])
    }

    @Test func removeMissingIDIsSafeNoOp() throws {
        let store = InMemoryEmergencyContactStore()
        try store.add(Self.contact(label: "A"))
        try store.remove(id: UUID())
        #expect(try store.contacts().count == 1)
    }

    @Test func removeAllClearsEverything() throws {
        let store = InMemoryEmergencyContactStore()
        try store.add(Self.contact(label: "A"))
        try store.add(Self.contact(label: "B"))
        try store.removeAll()
        #expect(try store.contacts().isEmpty)
    }

    // MARK: fresh-install orphan purge (Requirement 2.8)

    @Test func purgeOnFreshInstallClearsContactsAndMarks() throws {
        let marker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: false)
        let store = InMemoryEmergencyContactStore(
            contacts: [Self.contact(label: "orphan")],
            markerStore: marker
        )
        try store.purgeOrphansIfFreshInstall()
        #expect(try store.contacts().isEmpty)
        #expect(marker.hasLaunchedBefore())
    }

    @Test func purgeIsNoOpWhenNotFreshInstall() throws {
        let marker = InMemoryFreshInstallMarkerStore(hasLaunchedBefore: true)
        let store = InMemoryEmergencyContactStore(
            contacts: [Self.contact(label: "keep")],
            markerStore: marker
        )
        try store.purgeOrphansIfFreshInstall()
        #expect(try store.contacts().map(\.label) == ["keep"])
    }
}
