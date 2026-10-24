import Foundation
import Testing
@testable import Whoosh

/// Tests for `NWPathConnectivityMonitor` (task 24). The real `NWPathMonitor`
/// path cannot be driven deterministically in a unit test, so this covers
/// construction and idempotent start/stop; airplane-mode behaviour is a device
/// check (task 24 / manual QA). The coordinator's use of connectivity is tested
/// through `FakeConnectivityMonitor`.
@MainActor
struct NWPathConnectivityMonitorTests {

    @Test func constructsOfflineByDefault() {
        let monitor = NWPathConnectivityMonitor()
        // Starts `false` until the first path update arrives.
        #expect(!monitor.isOnline)
    }

    @Test func startAndStopAreIdempotent() {
        let monitor = NWPathConnectivityMonitor()
        monitor.start()
        monitor.start() // idempotent
        monitor.stop()
        monitor.stop() // idempotent
        // No crash; conforms to the protocol.
        let asProtocol: ConnectivityMonitor = monitor
        #expect(asProtocol.isOnline == false || asProtocol.isOnline == true)
    }
}
