import Foundation
import Testing
import WhooshWire
@testable import Whoosh

/// Focused tests for the phone "Apple Watch" readiness screen and the pre-ride
/// connect step (watch-companion task 22; owner's pre-ride connect request).
/// Driven by `FakeWatchConnection` — no WatchConnectivity, no UI.
@MainActor
struct WatchReadinessViewModelTests {

    @Test func buzzSucceedsWhenReachableAndRecordsFelt() async {
        let connection = FakeWatchConnection(isPaired: true, isWatchAppInstalled: true, isReachable: true)
        let vm = WatchReadinessViewModel(connection: connection)

        #expect(vm.canTestHaptics)
        await vm.buzzMyWatch()
        #expect(connection.sent == [nil])           // one plain test buzz
        #expect(vm.lastSendMessage != nil)

        vm.reportFelt(true)
        #expect(vm.lastHapticTestFelt == true)
        #expect(!vm.showsTroubleshooting)
    }

    @Test func threeMissesSurfaceTroubleshooting() {
        let vm = WatchReadinessViewModel(connection: FakeWatchConnection())
        vm.reportFelt(false)
        vm.reportFelt(false)
        #expect(!vm.showsTroubleshooting)
        vm.reportFelt(false)
        #expect(vm.showsTroubleshooting)
        // A felt buzz clears the streak.
        vm.reportFelt(true)
        #expect(!vm.showsTroubleshooting)
    }

    @Test func notInstalledHidesHapticsTestAndNamesPatterns() {
        let connection = FakeWatchConnection(isPaired: true, isWatchAppInstalled: false, isReachable: false)
        let vm = WatchReadinessViewModel(connection: connection)
        #expect(!vm.canTestHaptics)
        // Pattern previews use the public safety-critical catalog so a preview
        // feels like the real cue.
        #expect(vm.patterns.map(\.name) == HapticPatternSelector.safetyCritical.map(\.name))
    }

    @Test func previewSendsNamedPattern() async {
        let connection = FakeWatchConnection()
        let vm = WatchReadinessViewModel(connection: connection)
        let pattern = vm.patterns[0]
        await vm.previewPattern(pattern)
        #expect(connection.sent == [pattern.name])
    }
}

@MainActor
struct WatchConnectStepViewModelTests {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "watch.connect.test.\(UUID().uuidString)")!
        return suite
    }

    @Test func notPresentedWhenNoWatchPaired() {
        let connection = FakeWatchConnection(isPaired: false)
        #expect(!WatchConnectStepViewModel.shouldPresent(connection: connection, defaults: makeDefaults()))
    }

    @Test func presentedWhenPairedAndNotSuppressed() {
        let connection = FakeWatchConnection(isPaired: true)
        #expect(WatchConnectStepViewModel.shouldPresent(connection: connection, defaults: makeDefaults()))
    }

    @Test func dontShowAgainIsRemembered() {
        let defaults = makeDefaults()
        let connection = FakeWatchConnection(isPaired: true)
        let vm = WatchConnectStepViewModel(connection: connection, defaults: defaults)
        vm.dontShowAgain = true
        vm.persistSuppressionChoice()

        #expect(!WatchConnectStepViewModel.shouldPresent(connection: connection, defaults: defaults))
    }

    @Test func statusReflectsReachability() {
        let reachable = WatchConnectStepViewModel(
            connection: FakeWatchConnection(isPaired: true, isWatchAppInstalled: true, isReachable: true)
        )
        #expect(reachable.isConnected)
        #expect(reachable.statusTitle == "Watch connected")

        let unreachable = WatchConnectStepViewModel(
            connection: FakeWatchConnection(isPaired: true, isWatchAppInstalled: true, isReachable: false)
        )
        #expect(!unreachable.isConnected)
        #expect(unreachable.statusTitle == "Watch not reachable")
    }
}
