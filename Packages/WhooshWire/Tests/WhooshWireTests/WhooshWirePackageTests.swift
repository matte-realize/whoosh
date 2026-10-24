import Testing
@testable import WhooshWire

/// Trivial smoke test proving the package builds and `swift test` runs
/// (watch-companion task 3). Real wire/codec/allowlist tests arrive in tasks
/// 4 and 5.
@Suite("WhooshWire package")
struct WhooshWirePackageTests {
    @Test("module marker is present")
    func moduleMarker() {
        #expect(WhooshWire.name == "WhooshWire")
    }
}
