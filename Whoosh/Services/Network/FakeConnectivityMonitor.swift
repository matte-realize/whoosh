import Foundation

/// Scriptable `ConnectivityMonitor` for tests and previews.
///
/// Lives under `Services/Network/` so previews and the composition root can
/// inject it; tests reach it via `@testable import`. Tests drive it with
/// `setOnline(_:)` to flip reachability and fire `onChange` (only when the value
/// actually changes, mirroring `NWPathMonitor`, so a flapping path does not
/// spam the coordinator). Makes no network requests.
final class FakeConnectivityMonitor: ConnectivityMonitor {
    private(set) var isOnline: Bool
    var onChange: ((Bool) -> Void)?

    /// `true` between `start()` and `stop()`.
    private(set) var isObserving = false
    /// Number of `onChange` deliveries (distinct transitions while observing).
    private(set) var changeDeliveryCount = 0

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    func start() {
        isObserving = true
    }

    func stop() {
        isObserving = false
    }

    // MARK: Scripting API (test/preview driven)

    /// Set reachability. Fires `onChange` only when the value changes and the
    /// monitor is observing, matching the real monitor's de-duplicated updates.
    func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        guard isObserving else { return }
        changeDeliveryCount += 1
        onChange?(online)
    }
}
