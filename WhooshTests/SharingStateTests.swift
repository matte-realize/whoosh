import Testing
@testable import Whoosh

/// Tests for the derived `SharingState` (Requirement 12.15).
struct SharingStateTests {
    @Test func notSharedIsPrivate() {
        #expect(SharingState.forRide(sharePublicly: false, syncStatus: .synced) == .private)
        #expect(SharingState.forRide(sharePublicly: false, syncStatus: .localOnly) == .private)
    }

    @Test func sharedAndSyncedIsShared() {
        #expect(SharingState.forRide(sharePublicly: true, syncStatus: .synced) == .shared)
    }

    @Test func sharedButNotConfirmedIsSharingPending() {
        #expect(SharingState.forRide(sharePublicly: true, syncStatus: .pending) == .sharingPending)
        #expect(SharingState.forRide(sharePublicly: true, syncStatus: .localOnly) == .sharingPending)
        #expect(SharingState.forRide(sharePublicly: true, syncStatus: .failed) == .sharingPending)
    }

    @Test func titles() {
        #expect(SharingState.private.title == "Private")
        #expect(SharingState.shared.title == "Shared")
        #expect(SharingState.sharingPending.title == "Sharing pending")
    }
}
